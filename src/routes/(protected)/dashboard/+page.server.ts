import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase }, parent }) => {
	const { user } = await parent();

	if (!user) {
		throw error(401, 'Please sign in to view your dashboard.');
	}

	const { data: memberships, error: membershipsError } = await supabase
		.from('workspace_members')
		.select('workspace_id, role')
		.eq('user_id', user.id)
		.eq('status', 'active');

	if (membershipsError) {
		console.error('Could not load workspace memberships:', membershipsError.message);
		throw error(500, 'Unable to load your workspaces. Please try again.');
	}

	const workspaceIds = memberships.map(({ workspace_id }) => workspace_id);

	if (workspaceIds.length === 0) {
		return { workspaces: [] };
	}

	const [workspacesResult, membersResult] = await Promise.all([
		supabase
			.from('workspaces')
			.select('id, name, type, status')
			.in('id', workspaceIds)
			.eq('status', 'active'),
		supabase
			.from('workspace_members')
			.select('workspace_id')
			.in('workspace_id', workspaceIds)
			.eq('status', 'active')
	]);

	if (workspacesResult.error || membersResult.error) {
		console.error(
			'Could not load workspace details:',
			workspacesResult.error?.message ?? membersResult.error?.message
		);
		throw error(500, 'Unable to load your workspaces. Please try again.');
	}

	const membershipRole = new Map(memberships.map(({ workspace_id, role }) => [workspace_id, role]));
	const managerWorkspaceIds = workspacesResult.data
		.filter(
			({ id, type }) =>
				type === 'organization' && ['owner', 'admin'].includes(membershipRole.get(id) ?? '')
		)
		.map(({ id }) => id);

	let invitations: {
		id: string;
		workspace_id: string;
		email: string;
		role: string;
		expires_at: string;
	}[] = [];

	if (managerWorkspaceIds.length > 0) {
		const { data, error: invitationsError } = await supabase
			.from('workspace_invitations')
			.select('id, workspace_id, email, role, expires_at')
			.in('workspace_id', managerWorkspaceIds)
			.eq('status', 'pending')
			.gt('expires_at', new Date().toISOString())
			.order('created_at', { ascending: false });

		if (invitationsError) {
			console.error('Could not load workspace invitations:', invitationsError.message);
			throw error(500, 'Unable to load your workspace invitations. Please try again.');
		}

		invitations = data;
	}

	return {
		workspaces: workspacesResult.data.map((workspace) => ({
			...workspace,
			role: membershipRole.get(workspace.id) ?? 'member',
			memberCount: membersResult.data.filter(({ workspace_id }) => workspace_id === workspace.id)
				.length,
			invitations: invitations.filter(({ workspace_id }) => workspace_id === workspace.id)
		}))
	};
};
