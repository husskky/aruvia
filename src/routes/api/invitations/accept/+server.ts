import { createHash } from 'node:crypto';
import { error, json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ request, url, locals }) => {
	if (request.headers.get('origin') !== url.origin) {
		throw error(403, 'Cross-origin requests are not allowed.');
	}

	const { user } = await locals.safeGetSession();
	if (!user) {
		throw error(401, 'Sign in with the invited email address to continue.');
	}

	let input: { token?: unknown };
	try {
		input = await request.json();
	} catch {
		throw error(400, 'The invitation token is invalid.');
	}

	if (typeof input.token !== 'string' || !/^[0-9a-f]{64}$/.test(input.token)) {
		throw error(400, 'The invitation token is invalid.');
	}

	const tokenHash = createHash('sha256').update(input.token).digest('hex');
	const { data: workspaceId, error: acceptError } = await locals.supabase.rpc(
		'accept_workspace_invitation',
		{ target_token_hash: tokenHash }
	);

	if (acceptError) {
		if (acceptError.code === '42501') {
			throw error(403, 'Sign in with the confirmed email address that received this invitation.');
		}
		throw error(400, 'This invitation is invalid, expired, or has already been used.');
	}

	return json({ workspaceId });
};
