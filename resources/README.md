# Forge native learning library

The Library view includes the bundled `Sources/ForgeCore/Resources/resource-catalog.json` and saves validated downloads for offline restarts. `python3 scripts/sync-resource-catalog.py` copies the current public snapshot into the native bundle; local Swift builds run this step. On launch, the app checks the fixed public GitHub catalog URL, then checks every 15 minutes while running. Returning to the app or waking the Mac checks again when due. The interval starts after the previous request completes, and manual and automatic checks share a single request. Learning progress stays separate.

## Use the collection

`catalog.json` is the public, versioned resource database. `sources.json` controls categories, curated repositories, the discovery star threshold and collection bounds. Every fetched record includes its GitHub URL, observed star count, repository license identifier when GitHub recognizes it, last push time and collection time. License metadata is a pointer to review, not permission to redistribute repository contents.

With Node.js 20 or later, run from the repository root:

```sh
node --test scripts/resources/resource-catalog.test.mjs
node scripts/resources/check-catalog.mjs
node scripts/resources/resource-server.mjs refresh --config resources/sources.json --output resources/catalog.json
node scripts/resources/resource-server.mjs serve --config resources/sources.json --snapshot resources/catalog.json --port 8787
```

The optional local API is `http://127.0.0.1:8787/api/resources`. It accepts `category`, `q` and `limit` filters. Serving reads the local snapshot and makes no upstream requests. Refresh belongs in a server or CI job; an optional `GITHUB_TOKEN` comes from the environment and is never written to a snapshot. The API binds to loopback and accepts additional browser origins only through an explicit `--origins` list.

## Selection and freshness

Discovery searches public non-forked, non-archived repositories with at least 500 stars. Curated seeds may have fewer stars when they are useful primary references. The collection rejects archived, disabled and private sources, bounds upstream requests, deduplicates within each category, and ranks by category relevance, logarithmic star count and recent maintenance. Each category publishes at most 12 entries. A repository can belong to several categories.

Stars measure popularity, not correctness or suitability. No source code, README instructions or remote scripts are executed. Newly discovered entries are links and normalized metadata; they do not automatically enter assessment, warning, or training data. Application-content imports must use a dedicated adapter with source, format, rights and validation appropriate to that data.

The refresh job uses rate-limit cooldowns and conditional requests when its local sidecar exists. Hosted Actions runners start without that ignored sidecar, so daily CI fetches bounded fresh metadata; API serving always uses the public snapshot. Failed or incomplete sources preserve their last good entries with stale/error information. A cold start can provide clearly marked curated links with unknown star counts. Public snapshots omit the transport cache, stored in ignored `catalog.json.cache.json`. The API checks time-based freshness; the resource explorer labels the published snapshot and shows observation dates rather than describing historical metadata as a live feed.

## Automated updates

`.github/workflows/resources.yml` tests changes and, after it reaches the default branch, refreshes once daily or through **Run workflow**. A usable validated refresh commits only the public snapshot (and the native bundle copy in Forge for Mac). Partial refreshes publish validated last-good entries with stale/error information and a workflow warning. Fatal refresh or validation errors stop before committing; branch protections can also prevent the bot push. The workflow has read-only permissions for tests and grants content-write permission only to the refresh job.

The native app checks the public default-branch catalog on launch and every 15 minutes while running; **Refresh resources** can check sooner when no request is active. Validated downloads replace the saved catalog atomically. A network, validation or save failure leaves the previous saved copy intact, and an older source snapshot cannot replace a newer saved collection. A validated saved edition remains available across offline restarts, with the bundled edition as a fallback. The cache contains only public resource metadata and is separate from learning progress and its backups.

CDN caching can briefly delay a new snapshot. **Last successful check** records when the app last downloaded and validated a catalog; failed attempts do not advance it. The collection date and individual observation dates still describe the source metadata. The 15-minute app check does not change the daily server-side collection schedule or make older metadata fresh. Application-code changes still require a new app build. The optional local API reads its on-disk snapshot; no GitHub credential goes into the app bundle.

## Source policy

- **Programming foundations**: [freeCodeCamp/freeCodeCamp](https://github.com/freeCodeCamp/freeCodeCamp), [TheAlgorithms/Python](https://github.com/TheAlgorithms/Python), [ossu/computer-science](https://github.com/ossu/computer-science). Discovery: `topic:learn-to-code`.
- **Computer science pathways**: [ossu/computer-science](https://github.com/ossu/computer-science), [practical-tutorials/project-based-learning](https://github.com/practical-tutorials/project-based-learning). Discovery: `topic:computer-science`.

Implementation follows the official [GitHub search API](https://docs.github.com/en/rest/search/search), [repository search syntax](https://docs.github.com/en/search-github/searching-on-github/searching-for-repositories), and [API best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api).
