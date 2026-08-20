import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals: { supabase } }) => {
	const { data: claims } = await supabase.auth.getClaims();

	return {
		user: claims ?? null
	};
};
