import { createHash, randomBytes } from 'node:crypto';
import { error, json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const allowedRoles = new Set(['admin', 'treasurer', 'member', 'viewer']);

export const POST: RequestHandler = async ({ request, url, params, locals }) => {
	if (request.headers.get('origin') !== url.origin) {
		throw error(403, 'Cross-origin requests are not allowed.');
	}

	const { user } = await locals.safeGetSession();
	if (!user) {
		throw error(401, 'Please sign in to invite a member.');
	}

	let input: { email?: unknown; role?: unknown };
	try {
		input = await request.json();
	} catch {
		throw error(400, 'A valid JSON request is required.');
	}

	if (
		typeof input.email !== 'string' ||
		typeof input.role !== 'string' ||
		!allowedRoles.has(input.role)
	) {
		throw error(400, 'Provide an email address and a permitted workspace role.');
	}

	const token = randomBytes(32).toString('hex');
	const tokenHash = createHash('sha256').update(token).digest('hex');
	const { data: invitationId, error: invitationError } = await locals.supabase.rpc(
		'create_workspace_invitation',
		{
			target_workspace_id: params.workspaceId,
			target_email: input.email.trim().toLowerCase(),
			target_role: input.role,
			target_token_hash: tokenHash
		}
	);

	if (invitationError) {
		if (invitationError.code === '42501') {
			throw error(403, 'You do not have permission to invite members to this workspace.');
		}
		if (invitationError.code === '23505') {
			throw error(409, 'This user is already a member or has a pending invitation.');
		}
		throw error(400, 'Unable to create this invitation. Check the email and workspace.');
	}

	return json(
		{
			invitationId,
			invitationUrl: `${url.origin}/invitations/accept#token=${token}`
		},
		{ status: 201 }
	);
};
