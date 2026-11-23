# Verification evidence

The SonarQube export records the analysis of the Flask 1.1.0 source at commit `67662d5df54ba952392590dfd4d6956d2e1f0c99`. The later CI maintenance commit changes the pipeline configuration. It keeps the same Flask source and tests.

Minikube opened all five routes. Blue-green and rolling returned 1.1.0. Canary sent 19 of 160 requests to 1.1.0. A/B sent 79 of 160 identities to 1.1.0. Shadow returned 1.0.0 and the candidate access log recorded the mirrored request. The rollback check returned all five routes to 1.0.0. See the main README for the commands that repeat these checks.
