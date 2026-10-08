<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { Button } from '$lib/components/ui/button';

	let { data } = $props();
	let token = $state<string | null>(null);
	let message = $state('Checking your invitation…');
	let failed = $state(false);
	let submitting = $state(false);

	onMount(async () => {
		const fragment = new URLSearchParams(window.location.hash.slice(1));
		const pendingToken =
			fragment.get('token') ?? sessionStorage.getItem('aruvia_pending_invitation');

		if (!pendingToken || !/^[0-9a-f]{64}$/.test(pendingToken)) {
			failed = true;
			message = 'This invitation link is invalid or incomplete.';
			return;
		}

		sessionStorage.setItem('aruvia_pending_invitation', pendingToken);
		history.replaceState(null, '', window.location.pathname);

		if (!data.user) {
			message = 'Sign in with the email address that received this invitation.';
			window.location.assign(`${resolve('/login')}?next=%2Finvitations%2Faccept`);
			return;
		}

		token = pendingToken;
		message = `You’re signed in as ${data.user.email ?? 'your account'}. Accept this invitation to join the workspace.`;
	});

	async function respond(decision: 'accept' | 'decline') {
		if (!token) return;
		submitting = true;
		failed = false;

		try {
			const response = await fetch(`/api/invitations/${decision}`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ token })
			});

			if (!response.ok) {
				failed = true;
				message = (await response.json()).message ?? 'Unable to respond to this invitation.';
				return;
			}

			sessionStorage.removeItem('aruvia_pending_invitation');
			message = decision === 'accept' ? 'Invitation accepted.' : 'Invitation declined.';
			await goto(resolve('/dashboard'));
		} catch {
			failed = true;
			message = 'Unable to connect. Your invitation is still available to retry.';
		} finally {
			submitting = false;
		}
	}
</script>

<svelte:head>
	<title>Workspace invitation — Aruvia</title>
</svelte:head>

<main class="flex min-h-screen items-center justify-center p-6">
	<section class="w-full max-w-md rounded-xl border p-6 text-center" aria-live="polite">
		<h1 class="text-xl font-semibold">Workspace invitation</h1>
		<p class="mt-3 text-sm {failed ? 'text-destructive' : 'text-muted-foreground'}">{message}</p>
		{#if token}
			<div class="mt-6 flex justify-center gap-3">
				<Button disabled={submitting} onclick={() => respond('accept')}>Accept invitation</Button>
				<Button disabled={submitting} variant="outline" onclick={() => respond('decline')}
					>Decline</Button
				>
			</div>
		{/if}
		{#if failed}
			<a class="mt-5 inline-block text-sm underline" href={resolve('/dashboard')}
				>Back to dashboard</a
			>
			{#if data.user}
				<form method="POST" action="/auth/signout?next=%2Finvitations%2Faccept" class="mt-3">
					<button class="text-sm underline" type="submit">Sign in with another account</button>
				</form>
			{/if}
		{/if}
	</section>
</main>
