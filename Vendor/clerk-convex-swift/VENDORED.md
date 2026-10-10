# Vendored clerk-convex-swift

- Upstream: https://github.com/clerk/clerk-convex-swift, tag `0.1.0` (commit `5c7e62e`), MIT (`LICENSE`). Copied in `a8fdc6e`.
- Only `Sources/ClerkKitConvex/` is used; `Project.swift` compiles it straight into the app target.
- Why vendored: local patches in `ClerkConvexAuthProvider.swift` that upstream lacks:
  - fetch tokens from Clerk's `convex` JWT template (audience `convex`), including on `tokenRefreshed`, whose
    payload is Clerk's general session token that Convex rejects (`09fef50`);
  - sync Convex auth on `.signUpCompleted`, so a fresh sign-up authenticates without a session change.
- To drop the copy once upstream ships these fixes: add the package to `Tuist/Package.swift` and
  `.external(name: "ClerkConvex")` to the app target, remove the `Vendor/...` source glob, add `import ClerkConvex`
  where `ClerkConvexAuthProvider` is used, drop the `refreshedConvexToken` test, run `tuist install && tuist generate`,
  then delete this directory.
