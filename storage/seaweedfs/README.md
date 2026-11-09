# storage/seaweedfs — storage option A

For sovereign customers who have **no** object store and need one for the
landing zone. A reference SeaweedFS configuration plus the full infrastructure
guide (`GUIDE.md`, Korean, for hardware engineering teams). Nothing in Sumun
or the engine layer depends on it; any S3-compatible store (S3, MinIO under
the customer's licence, Ceph RGW) works the same (ADR 0006).

SeaweedFS-specific features (filer events, `weed mount`, erasure coding,
`remote.sync` cold tiering) are documented here only and are never required
by the product. Note the project's single-maintainer concentration when
recommending it.
