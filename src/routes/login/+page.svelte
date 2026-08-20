<script lang="ts">
	import { supabase } from '$lib/supabase/client';
	import { Button } from '$lib/components/ui/button';

	let loading = $state(false);
	let errorMessage = $state('');

	async function signInWithGoogle() {
		loading = true;
		errorMessage = '';

		const { error } = await supabase.auth.signInWithOAuth({
			provider: 'google',
			options: {
				redirectTo: `${window.location.origin}/auth/callback`
			}
		});

		if (error) {
			errorMessage = error.message;
			loading = false;
		}
	}
</script>

<svelte:head>
	<title>Masuk — Aruvia</title>
</svelte:head>

<div class="flex min-h-screen items-center justify-center p-6">
	<div class="w-full max-w-sm space-y-6">
		<div class="space-y-2 text-center">
			<h1 class="text-2xl font-semibold">Masuk ke Aruvia</h1>
			<p class="text-sm text-muted-foreground">
				Kelola keuangan pribadi dan organisasi dengan lebih terstruktur.
			</p>
		</div>

		<Button class="w-full" size="lg" onclick={signInWithGoogle} disabled={loading}>
			{loading ? 'Menghubungkan...' : 'Lanjutkan dengan Google'}
		</Button>

		{#if errorMessage}
			<p class="text-center text-sm text-destructive">
				{errorMessage}
			</p>
		{/if}
	</div>
</div>
