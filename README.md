# didacta-railway

Wrapper image for [Didacta Community](https://github.com/va360labs/didacta-io) (open LMS, Sustainable Use License) on Railway.

It runs the official `ghcr.io/va360labs/didacta-community` image, pinned by digest, with the web app moved onto Railway's injected
`PORT` and the first organisation and administrator created from `ADMIN_EMAIL` / `ADMIN_PASSWORD` through the setup endpoint
(`DIDACTA_SETUP_TOKEN`) as soon as the API answers, so there is no browser wizard to finish.

Needs a pgvector Postgres and Redis alongside it; the Railway template wires both. Licence of this wrapper: MIT. Didacta itself is
under the Didacta Sustainable Use License: internal use is free, managed hosting and resale need a commercial agreement.
