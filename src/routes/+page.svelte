<script lang="ts">
  import { onMount } from "svelte";
  import { getApiKey, saveApiKey, clearApiKey, fetchReviews } from "$lib/api";
  import type { ReviewItem, ReviewResponse } from "$lib/types";

  // State using Svelte 5 runes
  let apiKey = $state("");
  let inputKey = $state("");
  let showKey = $state(false);
  let isLoading = $state(false);
  let isInitialChecking = $state(true);
  let errorMessage = $state<string | null>(null);

  // Filter & Search
  let currentFilter = $state("waiting");
  let searchQuery = $state("");
  let selectedPlatform = $state("all");

  // Data
  let reviewData = $state<ReviewResponse | null>(null);
  let selectedItem = $state<ReviewItem | null>(null);

  onMount(async () => {
    try {
      const stored = await getApiKey();
      if (stored) {
        apiKey = stored;
        await loadReviews(stored, currentFilter);
      }
    } catch (err: any) {
      console.error("Initialization error:", err);
    } finally {
      isInitialChecking = false;
    }
  });

  async function handleSaveKey(e?: Event) {
    if (e) e.preventDefault();
    if (!inputKey.trim()) {
      errorMessage = "Please enter a valid API key (JWT).";
      return;
    }

    isLoading = true;
    errorMessage = null;

    try {
      // Validate by attempting to fetch
      const result = await fetchReviews(inputKey.trim(), currentFilter);
      await saveApiKey(inputKey.trim());
      apiKey = inputKey.trim();
      reviewData = result;
      inputKey = "";
    } catch (err: any) {
      errorMessage = err.message || "Failed to authenticate with Terra API.";
    } finally {
      isLoading = false;
    }
  }

  async function handleLogout() {
    if (confirm("Are you sure you want to remove your API Key?")) {
      await clearApiKey();
      apiKey = "";
      reviewData = null;
      selectedItem = null;
    }
  }

  async function loadReviews(keyToUse?: string, filter?: string) {
    const key = keyToUse || apiKey;
    if (!key) return;

    isLoading = true;
    errorMessage = null;

    try {
      reviewData = await fetchReviews(key, filter || currentFilter);
    } catch (err: any) {
      errorMessage = err.message || "Failed to fetch review queue.";
    } finally {
      isLoading = false;
    }
  }

  function handleFilterChange(newFilter: string) {
    currentFilter = newFilter;
    loadReviews(apiKey, newFilter);
  }

  // Format seconds into readable duration (e.g. 11h 6m)
  function formatDuration(seconds: number): string {
    if (!seconds || seconds <= 0) return "0m";
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    if (hrs > 0) {
      return `${hrs}h ${mins}m`;
    }
    return `${mins}m`;
  }

  // Relative or readable time format
  function formatTime(isoString: string): string {
    if (!isoString) return "-";
    try {
      const date = new Date(isoString);
      const now = new Date();
      const diffMs = now.getTime() - date.getTime();
      const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
      const diffDays = Math.floor(diffHours / 24);

      if (diffHours < 1) return "Just now";
      if (diffHours < 24) return `${diffHours}h ago`;
      if (diffDays < 7) return `${diffDays}d ago`;
      return date.toLocaleDateString();
    } catch {
      return isoString;
    }
  }

  // Filtered items derived from search and platform
  let filteredItems = $derived.by(() => {
    if (!reviewData?.items) return [];
    return reviewData.items.filter((item) => {
      const q = searchQuery.toLowerCase().trim();
      const matchesSearch =
        !q ||
        item.title?.toLowerCase().includes(q) ||
        item.projectTitle?.toLowerCase().includes(q) ||
        item.username?.toLowerCase().includes(q);

      const matchesPlatform =
        selectedPlatform === "all" ||
        item.platforms?.includes(selectedPlatform);

      return matchesSearch && matchesPlatform;
    });
  });

  // Aggregated summary stats
  let totalHours = $derived.by(() => {
    if (!filteredItems) return 0;
    const totalSec = filteredItems.reduce((acc, it) => acc + (it.seconds || 0), 0);
    return Math.round((totalSec / 3600) * 10) / 10;
  });

  let totalWarnings = $derived.by(() => {
    if (!filteredItems) return 0;
    return filteredItems.filter((i) => i.warn > 0 || i.danger > 0).length;
  });
</script>

<div class="min-h-screen flex flex-col bg-base-200">
  {#if isInitialChecking}
    <div class="flex-1 flex flex-col items-center justify-center gap-4">
      <span class="loading loading-spinner loading-lg text-primary"></span>
      <p class="text-sm opacity-70">Initializing Terra Reviewer...</p>
    </div>
  {:else if !apiKey}
    <!-- API Key Input View -->
    <div class="flex-1 flex items-center justify-center p-4">
      <div class="card w-full max-w-md bg-base-100 shadow-xl border border-base-300">
        <div class="card-body">
          <div class="flex items-center gap-3 mb-2">
            <div class="w-10 h-10 rounded-xl bg-primary text-primary-content flex items-center justify-center font-bold text-xl shadow-md">
              T
            </div>
            <div>
              <h1 class="card-title text-2xl font-bold">Terra Reviewer</h1>
              <p class="text-xs text-base-content/60">Hack Club Review Queue Client</p>
            </div>
          </div>

          <div class="divider my-1"></div>

          <p class="text-sm text-base-content/80 mb-2">
            Please enter your Terra API Key (JWT) to access the review queue.
          </p>

          {#if errorMessage}
            <div class="alert alert-error text-xs py-2 shadow-sm mb-3">
              <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-4 w-4" fill="none" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
              <span>{errorMessage}</span>
            </div>
          {/if}

          <form onsubmit={handleSaveKey} class="space-y-4">
            <div class="form-control">
              <label class="label pb-1" for="jwt-input">
                <span class="label-text font-medium">Terra API Key (JWT)</span>
              </label>
              <div class="relative">
                <input
                  id="jwt-input"
                  type={showKey ? "text" : "password"}
                  placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI..."
                  bind:value={inputKey}
                  class="input input-bordered w-full pr-12 text-sm font-mono"
                  disabled={isLoading}
                  required
                />
                <button
                  type="button"
                  class="btn btn-ghost btn-xs absolute right-2 top-3 text-xs opacity-70 hover:opacity-100"
                  onclick={() => (showKey = !showKey)}
                >
                  {showKey ? "Hide" : "Show"}
                </button>
              </div>
              <label class="label pt-1" for="jwt-input">
                <span class="label-text-alt text-base-content/50">Stored securely locally in your configuration.</span>
              </label>
            </div>

            <div class="card-actions justify-end pt-2">
              <button
                type="submit"
                class="btn btn-primary w-full"
                disabled={isLoading || !inputKey.trim()}
              >
                {#if isLoading}
                  <span class="loading loading-spinner loading-sm"></span>
                  Connecting...
                {:else}
                  Enter Review Queue
                {/if}
              </button>
            </div>
          </form>

          <div class="mt-4 p-3 bg-base-200 rounded-lg text-xs text-base-content/70 space-y-1">
            <p class="font-semibold text-base-content/90">Tip:</p>
            <p>Your token can be extracted from requests to <code>api.terra.hackclub.com</code> or your browser cookies / authorization headers when logged into Terra.</p>
          </div>
        </div>
      </div>
    </div>
  {:else}
    <!-- Main Application View -->
    <!-- Top Navbar -->
    <header class="navbar bg-base-100 border-b border-base-300 px-4 sticky top-0 z-30 shadow-sm">
      <div class="navbar-start gap-3">
        <div class="flex items-center gap-2">
          <div class="w-8 h-8 rounded-lg bg-primary text-primary-content flex items-center justify-center font-bold text-lg shadow-sm">
            T
          </div>
          <div>
            <h1 class="font-bold text-base leading-tight">Terra Reviewer</h1>
            <div class="flex items-center gap-1.5 text-xs text-base-content/60">
              <span class="badge badge-xs badge-success"></span>
              <span>Online</span>
              <span class="opacity-40">•</span>
              <span>Filter: <strong>{currentFilter}</strong></span>
            </div>
          </div>
        </div>
      </div>

      <div class="navbar-center hidden md:flex">
        <!-- Search bar -->
        <div class="join w-80">
          <input
            type="text"
            placeholder="Search projects, titles, users..."
            bind:value={searchQuery}
            class="input input-bordered input-sm join-item w-full"
          />
          {#if searchQuery}
            <button
              class="btn btn-sm btn-ghost join-item"
              onclick={() => (searchQuery = "")}
              title="Clear search"
            >
              ✕
            </button>
          {/if}
        </div>
      </div>

      <div class="navbar-end gap-2">
        <button
          class="btn btn-sm btn-outline gap-1"
          onclick={() => loadReviews()}
          disabled={isLoading}
          title="Refresh queue"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-4 w-4 {isLoading ? 'animate-spin' : ''}"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          <span class="hidden sm:inline">{isLoading ? "Refreshing..." : "Refresh"}</span>
        </button>

        <button
          class="btn btn-sm btn-ghost text-error"
          onclick={handleLogout}
          title="Logout / Change API Key"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
          </svg>
          <span class="hidden sm:inline">Logout</span>
        </button>
      </div>
    </header>

    <!-- Content Area -->
    <main class="flex-1 max-w-7xl w-full mx-auto p-4 space-y-4">
      {#if errorMessage}
        <div class="alert alert-error shadow-sm text-sm">
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-5 w-5" fill="none" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
          <div class="flex-1">
            <h3 class="font-bold">Error loading queue</h3>
            <p class="text-xs">{errorMessage}</p>
          </div>
          <button class="btn btn-xs btn-outline" onclick={() => loadReviews()}>Retry</button>
        </div>
      {/if}

      <!-- Stats Bar & Controls -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div class="stat bg-base-100 rounded-box border border-base-300 p-4 shadow-sm">
          <div class="stat-title text-xs">Total Waiting</div>
          <div class="stat-value text-primary text-2xl">{reviewData?.items?.length || 0}</div>
          <div class="stat-desc">In queue</div>
        </div>

        <div class="stat bg-base-100 rounded-box border border-base-300 p-4 shadow-sm">
          <div class="stat-title text-xs">Matching Filter</div>
          <div class="stat-value text-secondary text-2xl">{filteredItems.length}</div>
          <div class="stat-desc">Displayed</div>
        </div>

        <div class="stat bg-base-100 rounded-box border border-base-300 p-4 shadow-sm">
          <div class="stat-title text-xs">Warnings / Dangers</div>
          <div class="stat-value text-warning text-2xl">{totalWarnings}</div>
          <div class="stat-desc">Items flagged</div>
        </div>

        <div class="stat bg-base-100 rounded-box border border-base-300 p-4 shadow-sm">
          <div class="stat-title text-xs">Total Duration</div>
          <div class="stat-value text-accent text-2xl">{totalHours}h</div>
          <div class="stat-desc">Logged time</div>
        </div>
      </div>

      <!-- Filter Controls -->
      <div class="flex flex-wrap items-center justify-between gap-3 bg-base-100 p-3 rounded-box border border-base-300 shadow-sm">
        <!-- Queue Filter Tabs -->
        <div class="tabs tabs-boxed bg-base-200">
          <button
            class="tab tab-sm {currentFilter === 'waiting' ? 'tab-active' : ''}"
            onclick={() => handleFilterChange('waiting')}
          >
            Waiting
          </button>
          <button
            class="tab tab-sm {currentFilter === 'all' ? 'tab-active' : ''}"
            onclick={() => handleFilterChange('all')}
          >
            All
          </button>
          <button
            class="tab tab-sm {currentFilter === 'in_review' ? 'tab-active' : ''}"
            onclick={() => handleFilterChange('in_review')}
          >
            In Review
          </button>
        </div>

        <!-- Platform filter -->
        <div class="flex items-center gap-2">
          <span class="text-xs text-base-content/70">Platform:</span>
          <select
            class="select select-bordered select-xs"
            bind:value={selectedPlatform}
          >
            <option value="all">All Platforms</option>
            <option value="windows">Windows</option>
            <option value="linux">Linux</option>
            <option value="mac">macOS</option>
            <option value="other">Other</option>
          </select>
        </div>
      </div>

      <!-- Mobile Search Bar (only visible on small screens) -->
      <div class="md:hidden">
        <input
          type="text"
          placeholder="Search items..."
          bind:value={searchQuery}
          class="input input-bordered input-sm w-full"
        />
      </div>

      <!-- Review List -->
      {#if isLoading && (!reviewData || reviewData.items.length === 0)}
        <div class="p-12 text-center space-y-3">
          <span class="loading loading-spinner loading-lg text-primary"></span>
          <p class="text-sm opacity-60">Fetching review items from Terra API...</p>
        </div>
      {:else if filteredItems.length === 0}
        <div class="card bg-base-100 border border-base-300 p-12 text-center">
          <div class="max-w-xs mx-auto space-y-2">
            <div class="text-4xl">🎉</div>
            <h3 class="text-lg font-bold">No review items found</h3>
            <p class="text-xs text-base-content/60">
              {searchQuery || selectedPlatform !== "all"
                ? "Try clearing your search query or platform filters."
                : "The review queue is currently empty!"}
            </p>
          </div>
        </div>
      {:else}
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {#each filteredItems as item (item.id)}
            <div
              class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow duration-200 cursor-pointer flex flex-col justify-between"
              onclick={() => (selectedItem = item)}
              role="button"
              tabindex="0"
              onkeydown={(e) => e.key === 'Enter' && (selectedItem = item)}
            >
              <div class="card-body p-4 space-y-3">
                <!-- User & Queue Time Header -->
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    {#if item.profilePictureUrl}
                      <img
                        src={item.profilePictureUrl}
                        alt={item.username}
                        class="w-7 h-7 rounded-full object-cover bg-base-300"
                        onerror={(e) => {
                          // @ts-expect-error fallback
                          e.target.style.display = 'none';
                        }}
                      />
                    {:else}
                      <div class="w-7 h-7 rounded-full bg-base-300 flex items-center justify-center text-xs font-bold">
                        {item.username.slice(0, 1).toUpperCase()}
                      </div>
                    {/if}
                    <div class="text-xs font-semibold hover:underline">
                      @{item.username}
                    </div>
                  </div>
                  <span class="text-2xs text-base-content/50" title={item.submittedAt}>
                    {formatTime(item.submittedAt)}
                  </span>
                </div>

                <!-- Project & Submission Titles -->
                <div>
                  <div class="text-xs font-semibold text-primary/80 uppercase tracking-wider line-clamp-1">
                    {item.projectTitle || "Untitled Project"}
                  </div>
                  <h2 class="card-title text-base font-bold line-clamp-2 mt-0.5">
                    {item.title}
                  </h2>
                </div>

                <!-- Metadata badges -->
                <div class="flex flex-wrap gap-1.5 text-xs">
                  <span class="badge badge-sm badge-neutral">
                    Week {item.weekNumber}
                  </span>

                  {#if item.isUpdate}
                    <span class="badge badge-sm badge-info badge-outline">Update</span>
                  {:else}
                    <span class="badge badge-sm badge-success badge-outline">New Project</span>
                  {/if}

                  <span class="badge badge-sm badge-ghost font-mono">
                    ⏱ {formatDuration(item.seconds)}
                  </span>

                  {#each item.platforms || [] as plat}
                    <span class="badge badge-sm badge-outline capitalize">{plat}</span>
                  {/each}
                </div>

                <!-- Risk & Decision indicators -->
                <div class="flex flex-wrap items-center gap-1.5 pt-1 text-xs">
                  {#if item.danger > 0}
                    <span class="badge badge-sm badge-error gap-1">
                      ⚠️ Danger: {item.danger}
                    </span>
                  {/if}

                  {#if item.warn > 0}
                    <span class="badge badge-sm badge-warning gap-1">
                      ⚡ Warn: {item.warn}
                    </span>
                  {/if}

                  {#if item.decision}
                    <span class="badge badge-sm badge-secondary capitalize">
                      {item.decision}
                    </span>
                  {/if}

                  {#if item.claimedBy}
                    <span class="badge badge-sm badge-outline text-2xs opacity-75">
                      Claimed: {item.claimedBy}
                    </span>
                  {/if}
                </div>
              </div>

              <!-- Footer with ID & Open Action -->
              <div class="px-4 py-2 bg-base-200/50 border-t border-base-300 flex items-center justify-between text-xs text-base-content/60">
                <span class="font-mono text-2xs truncate max-w-[150px]" title={item.id}>
                  {item.id.slice(0, 8)}...
                </span>
                <span class="text-primary font-medium text-xs hover:underline flex items-center gap-1">
                  View details →
                </span>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    </main>
  {/if}

  <!-- Detail Modal -->
  {#if selectedItem}
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl bg-base-100 border border-base-300 p-6 space-y-4">
        <!-- Modal Header -->
        <div class="flex items-start justify-between">
          <div>
            <div class="flex items-center gap-2 mb-1">
              <span class="badge badge-primary badge-sm">Week {selectedItem.weekNumber}</span>
              {#if selectedItem.isUpdate}
                <span class="badge badge-info badge-sm">Update</span>
              {:else}
                <span class="badge badge-success badge-sm">New</span>
              {/if}
              <span class="badge badge-neutral badge-sm font-mono">{formatDuration(selectedItem.seconds)}</span>
            </div>
            <h3 class="font-bold text-xl leading-snug">{selectedItem.title}</h3>
            <p class="text-sm text-base-content/70 mt-0.5">{selectedItem.projectTitle}</p>
          </div>
          <button
            class="btn btn-sm btn-circle btn-ghost"
            onclick={() => (selectedItem = null)}
          >
            ✕
          </button>
        </div>

        <div class="divider my-0"></div>

        <!-- User Information -->
        <div class="flex items-center gap-3 p-3 bg-base-200 rounded-lg">
          {#if selectedItem.profilePictureUrl}
            <img
              src={selectedItem.profilePictureUrl}
              alt={selectedItem.username}
              class="w-12 h-12 rounded-full object-cover"
            />
          {:else}
            <div class="w-12 h-12 rounded-full bg-base-300 flex items-center justify-center font-bold text-base">
              {selectedItem.username.slice(0, 1).toUpperCase()}
            </div>
          {/if}
          <div class="flex-1 min-w-0">
            <h4 class="font-semibold text-sm">@{selectedItem.username}</h4>
            <p class="text-xs text-base-content/60 font-mono truncate">User ID: {selectedItem.userId}</p>
            <p class="text-xs text-base-content/60">Submitted: {new Date(selectedItem.submittedAt).toLocaleString()}</p>
          </div>
        </div>

        <!-- Attributes Grid -->
        <div class="grid grid-cols-2 gap-3 text-xs">
          <div class="p-3 bg-base-200 rounded-lg space-y-1">
            <span class="text-base-content/60 font-medium">Platforms</span>
            <div class="font-semibold flex flex-wrap gap-1">
              {#each selectedItem.platforms || [] as p}
                <span class="badge badge-xs badge-neutral capitalize">{p}</span>
              {/each}
            </div>
          </div>

          <div class="p-3 bg-base-200 rounded-lg space-y-1">
            <span class="text-base-content/60 font-medium">Evidence Status</span>
            <div class="font-semibold flex items-center gap-1.5">
              <span class="badge badge-xs {selectedItem.evidenceStatus === 'ok' ? 'badge-success' : 'badge-warning'}">
                {selectedItem.evidenceStatus}
              </span>
              <span class="text-2xs opacity-60">v{selectedItem.evidenceVersion}</span>
            </div>
          </div>

          <div class="p-3 bg-base-200 rounded-lg space-y-1">
            <span class="text-base-content/60 font-medium">Risk Flags</span>
            <div class="font-semibold flex gap-2">
              <span class={selectedItem.danger > 0 ? "text-error font-bold" : "text-base-content/60"}>
                Danger: {selectedItem.danger}
              </span>
              <span class={selectedItem.warn > 0 ? "text-warning font-bold" : "text-base-content/60"}>
                Warn: {selectedItem.warn}
              </span>
            </div>
          </div>

          <div class="p-3 bg-base-200 rounded-lg space-y-1">
            <span class="text-base-content/60 font-medium">Claim / Assignment</span>
            <div class="font-semibold">
              {selectedItem.claimedBy ? `@${selectedItem.claimedBy}` : "Unclaimed"}
            </div>
          </div>
        </div>

        {#if selectedItem.decision}
          <div class="p-3 bg-base-200 rounded-lg text-xs space-y-1">
            <span class="text-base-content/60 font-medium">Latest Decision</span>
            <div class="flex items-center gap-2">
              <span class="badge badge-sm badge-secondary capitalize">{selectedItem.decision}</span>
              {#if selectedItem.decidedBy}
                <span>by <strong>@{selectedItem.decidedBy}</strong></span>
              {/if}
              {#if selectedItem.decidedAt}
                <span class="text-base-content/50">({selectedItem.decidedAt})</span>
              {/if}
            </div>
          </div>
        {/if}

        <div class="modal-action flex justify-between items-center">
          <a
            href="https://terra.hackclub.com/review/{selectedItem.id}"
            target="_blank"
            rel="noopener noreferrer"
            class="btn btn-sm btn-primary gap-1"
          >
            Open on Terra Web ↗
          </a>
          <button class="btn btn-sm btn-ghost" onclick={() => (selectedItem = null)}>
            Close
          </button>
        </div>
      </div>
      <div
        class="modal-backdrop"
        onclick={() => (selectedItem = null)}
        onkeydown={(e) => e.key === 'Escape' && (selectedItem = null)}
        role="button"
        tabindex="0"
        aria-label="Close modal"
      ></div>
    </div>
  {/if}
</div>
