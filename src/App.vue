<template>
  <div class="min-h-screen">
    <div class="mx-auto max-w-4xl px-4 py-8">

      <!-- Header -->
      <div class="mb-8 text-center">
        <h1 class="text-3xl font-bold tracking-tight">Wake-on-LAN</h1>
        <p class="mt-2 text-muted-foreground">Manage and wake your network devices</p>
      </div>

      <!-- Device Modal Overlay (Add / Edit) -->
      <Transition name="modal">
        <div v-if="showDeviceModal" class="fixed inset-0 z-50 flex items-center justify-center">
          <div class="fixed inset-0 bg-black/80 backdrop-blur-sm" @click="closeDeviceModal"></div>
          <div class="relative z-50 w-[calc(100%-2rem)] max-w-md mx-4 sm:mx-auto rounded-lg border border-border bg-background p-4 sm:p-6 shadow-lg">
            <div class="mb-4">
              <h2 class="text-lg font-semibold">{{ editingDevice ? 'Edit Device' : 'Add New Device' }}</h2>
              <p class="text-sm text-muted-foreground">{{ editingDevice ? 'Update the device details below.' : 'Enter the device details to add it.' }}</p>
            </div>
            <form @submit.prevent="saveDevice" class="space-y-4">
              <div>
                <label class="label mb-1.5 block">Name</label>
                <input v-model="formDevice.name" class="input" placeholder="Living Room PC" />
              </div>
              <div>
                <label class="label mb-1.5 block">MAC Address <span class="text-red-400">*</span></label>
                <input v-model="formDevice.mac" class="input font-mono" placeholder="AA:BB:CC:DD:EE:FF"
                       required :disabled="!!editingDevice"
                       :class="{'opacity-50 cursor-not-allowed': !!editingDevice}" />
              </div>
              <div>
                <label class="label mb-1.5 block">Last Known IP <span class="text-muted-foreground font-normal">(optional)</span></label>
                <input v-model="formDevice.last_ip" class="input font-mono" placeholder="192.168.1.105" />
              </div>
              <div class="flex justify-end gap-2 pt-2">
                <button type="button" class="btn btn-outline" @click="closeDeviceModal">Cancel</button>
                <button type="submit" class="btn btn-primary" :disabled="loading">
                  {{ editingDevice ? 'Save Changes' : 'Add Device' }}
                </button>
              </div>
            </form>
          </div>
        </div>
      </Transition>

      <!-- Delete Confirm Modal -->
      <Transition name="modal">
        <div v-if="showDeleteModal" class="fixed inset-0 z-50 flex items-center justify-center">
          <div class="fixed inset-0 bg-black/80 backdrop-blur-sm" @click="closeDeleteModal"></div>
          <div class="relative z-50 w-[calc(100%-2rem)] max-w-sm mx-4 sm:mx-auto rounded-lg border border-border bg-background p-4 sm:p-6 shadow-lg">
            <div class="mb-4">
              <h2 class="text-lg font-semibold">Are you sure?</h2>
              <p class="text-sm text-muted-foreground mt-1">
                This will permanently delete <span class="font-medium text-foreground">{{ deleteTarget?.name }}</span>.
                This action cannot be undone.
              </p>
            </div>
            <div class="flex justify-end gap-2">
              <button type="button" class="btn btn-outline" @click="closeDeleteModal">Cancel</button>
              <button type="button" class="btn btn-destructive" @click="confirmDelete" :disabled="loading">Delete</button>
            </div>
          </div>
        </div>
      </Transition>

      <!-- Devices Card -->
      <div class="card">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-border px-4 sm:px-6 py-4">
          <div>
            <h2 class="text-lg font-semibold">Devices</h2>
            <p class="text-sm text-muted-foreground">{{ devices.length }} device{{ devices.length !== 1 ? 's' : '' }} configured</p>
          </div>
          <div class="flex gap-2">
            <button class="btn btn-outline btn-sm" @click="fetchDevices" :disabled="loading" title="Refresh">
              <svg class="h-4 w-4" :class="{'animate-spin': loading}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/></svg>
              <span class="hidden sm:inline">Refresh</span>
            </button>
            <button class="btn btn-primary btn-sm" @click="openAddModal">
              <svg class="h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
              Add Device
            </button>
          </div>
        </div>

        <!-- Loading -->
        <div v-if="loading && devices.length === 0" class="flex items-center justify-center py-16">
          <svg class="h-6 w-6 animate-spin text-muted-foreground" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>
        </div>

        <!-- Empty State -->
        <div v-else-if="devices.length === 0" class="flex flex-col items-center justify-center py-16 text-center">
          <svg class="h-10 w-10 text-muted-foreground/50 mb-3" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="8" x="5" y="2" rx="2"/><rect width="20" height="8" x="2" y="14" rx="2"/><path d="M6 18h.01"/><path d="M10 18h.01"/></svg>
          <p class="text-sm text-muted-foreground">No devices yet</p>
          <button class="btn btn-outline btn-sm mt-3" @click="openAddModal">Add your first device</button>
        </div>

        <!-- Device Table (desktop) -->
        <div v-else class="hidden sm:block overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="border-b border-border text-left">
                <th class="px-6 py-3 text-xs font-medium uppercase tracking-wider text-muted-foreground">Name</th>
                <th class="px-6 py-3 text-xs font-medium uppercase tracking-wider text-muted-foreground">MAC</th>
                <th class="px-6 py-3 text-xs font-medium uppercase tracking-wider text-muted-foreground">IP</th>
                <th class="px-6 py-3 text-xs font-medium uppercase tracking-wider text-muted-foreground">Status</th>
                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wider text-muted-foreground">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="dev in devices" :key="dev.mac"
                  class="border-b border-border last:border-0 transition-colors hover:bg-muted/50">
                <td class="px-6 py-3 text-sm font-medium">{{ dev.name }}</td>
                <td class="px-6 py-3 text-sm font-mono text-muted-foreground">{{ dev.mac }}</td>
                <td class="px-6 py-3 text-sm font-mono text-muted-foreground">{{ dev.last_ip || '—' }}</td>
                <td class="px-6 py-3">
                  <span :class="dev.online ? 'badge-success' : 'badge-danger'" class="badge">
                    <span class="mr-1 h-1.5 w-1.5 rounded-full" :class="dev.online ? 'bg-emerald-400' : 'bg-red-400'"></span>
                    {{ dev.online ? 'Online' : 'Offline' }}
                  </span>
                </td>
                <td class="px-6 py-3 text-right">
                  <div class="inline-flex gap-1">
                    <button class="btn btn-ghost btn-icon btn-sm" @click="wake(dev.mac)" :disabled="loading" title="Wake">
                      <svg class="h-4 w-4 text-emerald-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18.36 6.64A9 9 0 0 1 20.77 15"/><path d="M6.16 6.16a9 9 0 1 0 12.68 12.68"/><path d="M12 2v4"/><path d="m2 2 20 20"/><circle cx="12" cy="12" r="4"/></svg>
                    </button>
                    <button class="btn btn-ghost btn-icon btn-sm" @click="openEditModal(dev)" :disabled="loading" title="Edit">
                      <svg class="h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
                    </button>
                    <button class="btn btn-ghost btn-icon btn-sm" @click="openDeleteModal(dev)" :disabled="loading" title="Delete">
                      <svg class="h-4 w-4 text-red-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/></svg>
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Device Cards (mobile) -->
        <div v-if="devices.length > 0" class="sm:hidden divide-y divide-border">
          <div v-for="dev in devices" :key="dev.mac" class="p-4 space-y-3">
            <div class="flex items-start justify-between">
              <div>
                <p class="text-sm font-medium">{{ dev.name }}</p>
                <p class="text-xs font-mono text-muted-foreground mt-0.5">{{ dev.mac }}</p>
              </div>
              <span :class="dev.online ? 'badge-success' : 'badge-danger'" class="badge">
                <span class="mr-1 h-1.5 w-1.5 rounded-full" :class="dev.online ? 'bg-emerald-400' : 'bg-red-400'"></span>
                {{ dev.online ? 'Online' : 'Offline' }}
              </span>
            </div>
            <div v-if="dev.last_ip" class="text-xs text-muted-foreground">
              IP: <span class="font-mono">{{ dev.last_ip }}</span>
            </div>
            <div class="flex gap-2">
              <button class="btn btn-outline btn-sm flex-1" @click="wake(dev.mac)" :disabled="loading">
                <svg class="h-4 w-4 text-emerald-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18.36 6.64A9 9 0 0 1 20.77 15"/><path d="M6.16 6.16a9 9 0 1 0 12.68 12.68"/><path d="M12 2v4"/><path d="m2 2 20 20"/><circle cx="12" cy="12" r="4"/></svg>
                Wake
              </button>
              <button class="btn btn-ghost btn-icon-sm" @click="openEditModal(dev)" :disabled="loading" title="Edit">
                <svg class="h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
              </button>
              <button class="btn btn-ghost btn-icon-sm" @click="openDeleteModal(dev)" :disabled="loading" title="Delete">
                <svg class="h-4 w-4 text-red-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/></svg>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Toast -->
      <Transition enter-active-class="transition ease-out duration-300" enter-from-class="translate-y-2 opacity-0" enter-to-class="translate-y-0 opacity-100"
                  leave-active-class="transition ease-in duration-200" leave-from-class="translate-y-0 opacity-100" leave-to-class="translate-y-2 opacity-0">
        <div v-if="toastVisible" class="fixed bottom-4 right-4 z-50 max-w-sm rounded-lg border border-border bg-background p-4 shadow-lg">
          <div class="flex items-start gap-3">
            <svg v-if="toastType === 'success'" class="h-5 w-5 shrink-0 text-emerald-400 mt-0.5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
            <svg v-else class="h-5 w-5 shrink-0 text-red-400 mt-0.5" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/></svg>
            <p class="text-sm">{{ toastMessage }}</p>
            <button class="ml-auto shrink-0 text-muted-foreground hover:text-foreground" @click="toastVisible = false">
              <svg class="h-4 w-4" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
            </button>
          </div>
        </div>
      </Transition>

      <!-- Footer -->
      <footer class="mt-8 text-center text-xs text-muted-foreground py-4 border-t border-border">
        &copy; <sytong>Stupid WOL</sytong> for Mango People
      </footer>

    </div>
  </div>
</template>

<script>
export default {
  data() {
    return {
      devices: [],
      formDevice: { name: '', mac: '', last_ip: '' },
      editingDevice: null,
      deleteTarget: null,
      loading: false,
      showDeviceModal: false,
      showDeleteModal: false,
      toastVisible: false,
      toastMessage: '',
      toastType: 'success',
      toastTimer: null,
      pollInterval: null
    }
  },
  mounted() {
    this.fetchDevices();
    this.pollInterval = setInterval(() => this.refreshStatus(), 10000);
  },
  beforeUnmount() {
    clearInterval(this.pollInterval);
  },
  methods: {
    async refreshStatus() {
      if (this.loading) return;
      try {
        const res = await fetch('/api/devices');
        if (!res.ok) return;
        this.devices = await res.json();
      } catch { /* ignore polling errors */ }
    },
    async fetchDevices() {
      this.loading = true;
      try {
        const res = await fetch('/api/devices');
        if (!res.ok) throw new Error('Failed to load devices');
        this.devices = await res.json();
      } catch (err) {
        this.showToast(err.message, 'danger');
      } finally {
        this.loading = false;
      }
    },

    openAddModal() {
      this.editingDevice = null;
      this.formDevice = { name: '', mac: '', last_ip: '' };
      this.showDeviceModal = true;
    },

    openEditModal(dev) {
      this.editingDevice = dev.mac;
      this.formDevice = { name: dev.name, mac: dev.mac, last_ip: dev.last_ip || '' };
      this.showDeviceModal = true;
    },

    closeDeviceModal() {
      this.showDeviceModal = false;
      this.editingDevice = null;
    },

    async saveDevice() {
      if (!this.formDevice.mac.trim()) return;
      this.loading = true;
      try {
        if (this.editingDevice) {
          const res = await fetch(`/api/devices/${encodeURIComponent(this.editingDevice)}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(this.formDevice)
          });
          if (!res.ok) {
            const err = await res.json();
            throw new Error(err.error || 'Failed to update');
          }
          this.showToast('Device updated', 'success');
        } else {
          const res = await fetch('/api/devices', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(this.formDevice)
          });
          if (!res.ok) {
            const err = await res.json();
            throw new Error(err.error || 'Failed to add');
          }
          const result = await res.json();
          const ipMsg = result.last_ip ? ` (IP: ${result.last_ip})` : '';
          this.showToast('Device added' + ipMsg, 'success');
        }
        this.closeDeviceModal();
        await this.fetchDevices();
      } catch (err) {
        this.showToast(err.message, 'danger');
      } finally {
        this.loading = false;
      }
    },

    openDeleteModal(dev) {
      this.deleteTarget = dev;
      this.showDeleteModal = true;
    },

    closeDeleteModal() {
      this.showDeleteModal = false;
      this.deleteTarget = null;
    },

    async confirmDelete() {
      if (!this.deleteTarget) return;
      this.loading = true;
      try {
        const res = await fetch(`/api/devices/${encodeURIComponent(this.deleteTarget.mac)}`, {
          method: 'DELETE'
        });
        if (!res.ok) {
          const err = await res.json();
          throw new Error(err.error || 'Failed to delete');
        }
        this.showToast(`${this.deleteTarget.name} deleted`, 'success');
        this.closeDeleteModal();
        await this.fetchDevices();
      } catch (err) {
        this.showToast(err.message, 'danger');
      } finally {
        this.loading = false;
      }
    },

    async wake(mac) {
      this.loading = true;
      try {
        const res = await fetch(`/api/wake/${mac}`, { method: 'POST' });
        const data = await res.json();
        if (res.ok) {
          this.showToast(data.message, 'success');
          setTimeout(() => this.fetchDevices(), 4000);
        } else {
          throw new Error(data.error || 'Wake failed');
        }
      } catch (err) {
        this.showToast(err.message, 'danger');
      } finally {
        this.loading = false;
      }
    },

    showToast(message, type = 'success') {
      clearTimeout(this.toastTimer);
      this.toastMessage = message;
      this.toastType = type;
      this.toastVisible = true;
      this.toastTimer = setTimeout(() => { this.toastVisible = false; }, 4000);
    }
  }
}
</script>
