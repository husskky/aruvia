<script lang="ts">
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
			<h2 class="font-medium">Authenticated</h2>

			<p class="mt-2 text-sm text-muted-foreground">Kamu berhasil masuk ke Aruvia.</p>

			<pre class="mt-4 overflow-auto rounded-lg bg-muted p-4 text-xs">{JSON.stringify(
					data.claims,
					null,
					2
				)}</pre>
		</section>
		<form method="POST" action="/auth/signout">
			<button
				type="submit"
				class="rounded-lg border px-4 py-2 text-sm font-medium transition hover:bg-muted"
			>
				Keluar
			</button>
		</form>
	</main>
</div>
