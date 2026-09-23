<script lang="ts">
	import { Button } from '$lib/components/ui/button';
</script>

<svelte:head>
	<title>Aruvia — Kelola Keuangan Lebih Terstruktur</title>
</svelte:head>

<div class="flex min-h-screen flex-col items-center justify-center p-6 text-center">
	<h1 class="text-4xl font-bold tracking-tight sm:text-5xl">Aruvia</h1>
	<p class="mt-4 max-w-md text-lg text-muted-foreground">
		Kelola keuangan pribadi dan organisasi dengan lebih terstruktur.
	</p>
	<div class="mt-8">
		<Button href="/login" size="lg">Mulai Sekarang</Button>
	</div>
</div>
