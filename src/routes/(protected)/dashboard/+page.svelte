<script lang="ts">
	import { Button } from '$lib/components/ui/button';

	let { data } = $props();
</script>

<svelte:head>
	<title>Dashboard — Aruvia</title>
</svelte:head>

<div class="min-h-screen p-6">
	<main class="mx-auto max-w-7xl">
		<header class="mb-8">
			<p class="text-sm text-muted-foreground">Aruvia</p>

			<h1 class="mt-1 text-3xl font-semibold tracking-tight">Dashboard</h1>

			<p class="mt-2 text-muted-foreground">
				Kelola keuangan pribadi dan organisasi dari satu tempat.
			</p>
		</header>

		<section class="rounded-xl border p-6">
			<h2 class="font-medium">
				Selamat datang{data.user?.email ? `, ${data.user.email}` : ''}
			</h2>

			<p class="mt-2 text-sm text-muted-foreground">Kamu berhasil masuk ke Aruvia.</p>
		</section>

		<form method="POST" action="/auth/signout" class="mt-6">
			<Button type="submit" variant="outline">Keluar</Button>
		</form>
	</main>
</div>
