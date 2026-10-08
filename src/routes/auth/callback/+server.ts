import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ url, locals: { supabase } }) => {
	const code = url.searchParams.get('code');
	const next = url.searchParams.get('next');
	const destination = next === '/invitations/accept' ? next : '/dashboard';

	if (!code) {
		throw redirect(303, '/login?error=auth_callback_failed');
	}

	const { error } = await supabase.auth.exchangeCodeForSession(code);

	if (error) {
		console.error('OAuth callback error:', error.message);
		throw redirect(303, '/login?error=auth_callback_failed');
	}

	throw redirect(303, destination);
};
