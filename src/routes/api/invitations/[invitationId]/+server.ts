import { error, json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const DELETE: RequestHandler = async ({ request, url, params, locals }) => {
	if (request.headers.get('origin') !== url.origin) {
		throw error(403, 'Cross-origin requests are not allowed.');
	}

	const { user } = await locals.safeGetSession();
	if (!user) {
		throw error(401, 'Please sign in to revoke an invitation.');
	}

	const { error: revokeError } = await locals.supabase.rpc('revoke_workspace_invitation', {
		target_invitation_id: params.invitationId
	});

	if (revokeError) {
		if (revokeError.code === '42501') {
			throw error(403, 'You do not have permission to revoke this invitation.');
		}
		if (revokeError.code === 'P0002') {
			throw error(404, 'Invitation not found.');
		}
		throw error(409, 'This invitation is no longer pending.');
	}

	return json({ success: true });
};
