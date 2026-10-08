import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ locals: { supabase }, url }) => {
	await supabase.auth.signOut();

	const destination =
		url.searchParams.get('next') === '/invitations/accept'
			? '/login?next=%2Finvitations%2Faccept'
			: '/login';
	throw redirect(303, destination);
};
