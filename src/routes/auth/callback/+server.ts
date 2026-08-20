import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ url, locals: { supabase } }) => {
	const code = url.searchParams.get('code');

	if (!code) {
		throw redirect(303, '/login?error=auth_callback_failed');
	}

	const { error } = await supabase.auth.exchangeCodeForSession(code);

	if (error) {
		console.error('OAuth callback error:', error.message);
		throw redirect(303, '/login?error=auth_callback_failed');
	}

	throw redirect(303, '/dashboard');
};
