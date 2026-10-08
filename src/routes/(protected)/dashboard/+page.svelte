<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { Button } from '$lib/components/ui/button';

	let { data } = $props();
	let inviteEmails = $state<Record<string, string>>({});
	let inviteRoles = $state<Record<string, string>>({});
	let inviteLinks = $state<Record<string, string>>({});
	let inviteErrors = $state<Record<string, string>>({});
	let inviting = $state<Record<string, boolean>>({});
	let revoking = $state<Record<string, boolean>>({});
	let revokeErrors = $state<Record<string, string>>({});

	async function createInvitation(event: SubmitEvent, workspaceId: string) {
		event.preventDefault();
		inviting[workspaceId] = true;
		inviteErrors[workspaceId] = '';
		inviteLinks[workspaceId] = '';

		try {
			const response = await fetch(`/api/workspaces/${workspaceId}/invitations`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					email: inviteEmails[workspaceId],
					role: inviteRoles[workspaceId] ?? 'member'
				})
			});
			const result = await response.json();

			if (!response.ok) {
				inviteErrors[workspaceId] = result.message ?? 'Tidak dapat membuat undangan.';
				return;
			}

			inviteLinks[workspaceId] = result.invitationUrl;
		} catch {
			inviteErrors[workspaceId] = 'Tidak dapat terhubung. Coba lagi.';
		} finally {
			inviting[workspaceId] = false;
		}
	}

	async function copyInvitationLink(workspaceId: string) {
		const link = inviteLinks[workspaceId];
		if (link) await navigator.clipboard.writeText(link);
	}

	async function revokeInvitation(invitationId: string) {
		revoking[invitationId] = true;
		revokeErrors[invitationId] = '';

		try {
			const response = await fetch(`/api/invitations/${invitationId}`, { method: 'DELETE' });
			if (!response.ok) {
				const result = await response.json();
				revokeErrors[invitationId] = result.message ?? 'Tidak dapat membatalkan undangan.';
				return;
			}

			await invalidateAll();
		} catch {
			revokeErrors[invitationId] = 'Tidak dapat terhubung. Coba lagi.';
		} finally {
			revoking[invitationId] = false;
		}
	}
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

		<section class="mt-8" aria-labelledby="workspaces-heading">
			<div class="mb-4">
				<h2 id="workspaces-heading" class="text-xl font-semibold">Workspace kamu</h2>
				<p class="mt-1 text-sm text-muted-foreground">
					Workspace pribadi dan organisasi yang bisa kamu akses.
				</p>
			</div>

			{#if data.workspaces.length === 0}
				<div class="rounded-xl border p-6 text-sm text-muted-foreground">
					Belum ada workspace aktif untuk akun ini.
				</div>
			{:else}
				<ul class="grid gap-4 md:grid-cols-2">
					{#each data.workspaces as workspace (workspace.id)}
						<li class="rounded-xl border p-6">
							<div class="flex items-start justify-between gap-4">
								<div>
									<h3 class="font-medium">{workspace.name}</h3>
									<p class="mt-1 text-sm text-muted-foreground capitalize">
										{workspace.type} · {workspace.role}
									</p>
								</div>
								<p class="shrink-0 text-sm text-muted-foreground">
									{workspace.memberCount} anggota aktif
								</p>
							</div>

							{#if workspace.type === 'organization' && ['owner', 'admin'].includes(workspace.role)}
								<form
									class="mt-5 space-y-3 border-t pt-5"
									onsubmit={(event) => createInvitation(event, workspace.id)}
								>
									<h4 class="text-sm font-medium">Undang anggota</h4>
									<label class="sr-only" for="invite-email-{workspace.id}">Email anggota</label>
									<input
										id="invite-email-{workspace.id}"
										type="email"
										required
										maxlength="254"
										autocomplete="email"
										placeholder="Email anggota"
										value={inviteEmails[workspace.id] ?? ''}
										oninput={(event) => (inviteEmails[workspace.id] = event.currentTarget.value)}
										class="w-full rounded-md border bg-background px-3 py-2 text-sm"
									/>
									<label class="sr-only" for="invite-role-{workspace.id}">Peran anggota</label>
									<select
										id="invite-role-{workspace.id}"
										value={inviteRoles[workspace.id] ?? 'member'}
										onchange={(event) => (inviteRoles[workspace.id] = event.currentTarget.value)}
										class="w-full rounded-md border bg-background px-3 py-2 text-sm"
									>
										<option value="admin">Admin</option>
										<option value="treasurer">Bendahara</option>
										<option value="member">Anggota</option>
										<option value="viewer">Pengamat</option>
									</select>
									<Button type="submit" variant="outline" disabled={inviting[workspace.id]}>
										{inviting[workspace.id] ? 'Membuat tautan…' : 'Buat tautan undangan'}
									</Button>
									{#if inviteErrors[workspace.id]}
										<p class="text-sm text-destructive" role="alert">
											{inviteErrors[workspace.id]}
										</p>
									{/if}
									{#if inviteLinks[workspace.id]}
										<div class="space-y-2">
											<p class="text-sm text-muted-foreground">
												Tautan berlaku selama 7 hari. Kirimkan hanya kepada orang yang diundang.
											</p>
											<div class="flex gap-2">
												<input
													aria-label="Tautan undangan"
													readonly
													value={inviteLinks[workspace.id]}
													class="min-w-0 flex-1 rounded-md border bg-muted px-3 py-2 text-xs"
												/>
												<Button
													type="button"
													variant="outline"
													onclick={() => copyInvitationLink(workspace.id)}>Salin</Button
												>
											</div>
										</div>
									{/if}
								</form>
							{/if}

							{#if workspace.invitations.length > 0}
								<div class="mt-5 space-y-3 border-t pt-5">
									<h4 class="text-sm font-medium">Undangan menunggu</h4>
									{#each workspace.invitations as invitation (invitation.id)}
										<div class="flex items-start justify-between gap-3 text-sm">
											<div class="min-w-0">
												<p class="break-all">{invitation.email}</p>
												<p class="text-muted-foreground">
													{invitation.role} · berlaku hingga
													{new Date(invitation.expires_at).toISOString().slice(0, 10)}
												</p>
											</div>
											<Button
												type="button"
												variant="outline"
												disabled={revoking[invitation.id]}
												onclick={() => revokeInvitation(invitation.id)}
											>
												{revoking[invitation.id] ? 'Membatalkan…' : 'Batalkan'}
											</Button>
										</div>
										{#if revokeErrors[invitation.id]}
											<p class="text-sm text-destructive" role="alert">
												{revokeErrors[invitation.id]}
											</p>
										{/if}
									{/each}
								</div>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		<form method="POST" action="/auth/signout" class="mt-6">
			<Button type="submit" variant="outline">Keluar</Button>
		</form>
	</main>
</div>
