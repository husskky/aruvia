import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals: { safeGetSession }, cookies }) => {
	const { session, user } = await safeGetSession();
	const supabaseAuthCookies = cookies
		.getAll()
		.filter(({ name }) => /^sb-.+-auth-token(?:\.\d+)?$/.test(name));

	return {
		session,
		user,
		cookies: supabaseAuthCookies
	};
};
