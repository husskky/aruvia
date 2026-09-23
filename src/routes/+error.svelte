<script lang="ts">
	import { page } from '$app/state';
</script>

<svelte:head>
	<title>{page.status} — Aruvia</title>
</svelte:head>

<div class="flex min-h-screen flex-col items-center justify-center p-6 text-center">
	<h1 class="text-6xl font-bold tracking-tight">{page.status}</h1>
	<p class="mt-4 text-lg text-muted-foreground">{page.error?.message}</p>
	<a
		href="/"
		class="mt-8 text-sm text-muted-foreground underline underline-offset-4 hover:text-foreground"
	>
		Kembali ke beranda
	</a>
</div>

