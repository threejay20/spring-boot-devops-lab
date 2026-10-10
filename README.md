# spring-boot-devops-lab

A small Spring Boot service, used to practise the full path a Java service takes to production: build, containerise, deploy with zero downtime, automate with a pipeline, and stream events through Kafka.

## What's here so far

| Stage | What it covers | Status |
| --- | --- | --- |
| 1. Build | Spring Boot app with a `/hello` endpoint and Actuator health checks, built with Maven | Done |
| 2. Containerise | Multi-stage Dockerfile, JRE-only runtime image, non-root user, container-aware memory settings | Done |
| 3. Deploy | Helm chart on a local Kubernetes cluster (kind) with rolling updates, probes and graceful shutdown | Done |
| 4. Automate | GitHub Actions pipeline that builds, tests, checks the Helm chart and publishes the image to GitHub Container Registry | Done |
| 5. Stream | Kafka lab: keys and partitions, consumer groups, consumer lag and consumer scaling (`kafka/run-lab.sh`) | Done |

## Get the image

Every push to `main` publishes a new image, tagged with the commit ID and `latest`:

```bash
docker pull ghcr.io/threejay20/spring-boot-devops-lab:latest
docker run -d -p 8080:8080 --name app ghcr.io/threejay20/spring-boot-devops-lab:latest
curl localhost:8080/hello
```

## Run it

With Maven:

```bash
./mvnw clean package
java -jar target/demo-0.0.1-SNAPSHOT.jar
curl localhost:8080/hello
curl localhost:8080/actuator/health/readiness
```

With Docker:

```bash
docker build -t spring-boot-devops-lab:1.1 .
docker run -d -p 8080:8080 --name app spring-boot-devops-lab:1.1
curl localhost:8080/hello
```

On a local Kubernetes cluster with kind and Helm:

```bash
kind create cluster --name lab
kind load docker-image spring-boot-devops-lab:1.1 --name lab
helm upgrade --install demo ./chart --atomic --timeout 5m
kubectl get pods
```

The Kafka lab, with Docker:

```bash
./kafka/run-lab.sh
```

Settings change without a rebuild. `SERVER_PORT` moves the port, and `APP_MESSAGE` (set through the chart's `message` value) changes the `/hello` reply.

## Design decisions

**Two-stage Dockerfile.** Maven and the full JDK build the JAR in the first stage, and only the JAR is copied into a JRE-only image. The final image has no compiler, build tools or source code, and comes out at about 138 MB.

**Dependency caching.** `pom.xml` is copied and dependencies downloaded before the source code, so code changes don't trigger a full re-download.

**Non-root user.** The app runs as `appuser`, not root.

**Image labels.** The image sets its own OCI labels for title, description and source repository, instead of inheriting the base image's.

**Container-aware memory.** The heap is set with `-XX:MaxRAMPercentage=75` instead of a fixed `-Xmx`, so it scales with the container's memory limit and leaves room for non-heap memory.

**Rolling updates that never drop capacity.** `maxSurge: 1` and `maxUnavailable: 0`, so a new pod must be ready before an old one is removed.

**Three probes.** A startup probe gives Java time to start before other checks begin, a readiness probe keeps traffic away until the app is ready, and a liveness probe restarts a pod that stops responding. All point at Spring Boot Actuator.

**Graceful shutdown.** A 10-second `preStop` pause lets the load balancer stop sending traffic before the pod shuts down, and Spring Boot finishes requests already in progress.

**Safe deploys.** Releases use `helm upgrade --install --atomic`, which rolls back automatically if the new version never becomes ready. Charts are checked with `helm template` before deploying, because `helm lint` only checks structure.

**Continuous integration.** Every push and pull request builds the app and runs the tests, then checks the Helm chart with `helm lint` and `helm template`. Only pushes to `main` publish an image, tagged with the commit ID and `latest`, so untested code never reaches the registry. The pipeline gets the smallest permissions it needs, caches Maven libraries between runs, and cancels older runs when a newer push arrives.

**Ready for AWS.** Publishing to Amazon ECR instead of GitHub's registry is a sign-in change: an IAM role trusted through OIDC for this repository and branch, with no stored keys. The build, test and tagging steps stay the same.

**Kafka keys for ordering.** Trades use the bond ID as the message key, so every trade for one bond lands in the same partition and stays in order. The lab uses one broker; production would use a replication factor of 3, `min.insync.replicas=2` and `acks=all`, so a broker can fail without losing data.

## Experiments

### Memory: the same image in a 256 MB container

| Heap setting | Result |
| --- | --- |
| Fixed `-Xmx512m` (bigger than the container) | `OOMKilled=true`, exit code 137, and no `OutOfMemoryError` in the app logs: the container was killed from outside |
| `-XX:MaxRAMPercentage=75` | Ran normally and answered requests |

### Zero downtime: a client calling the service 5 times a second during a rollout

| Chart setting | Requests | Failed |
| --- | --- | --- |
| Probes and preStop on (`safeRollout=true`) | 289 | 0 |
| Probes and preStop off (`safeRollout=false`) | 114 | 18 (about 1 in 6) |

Without the probes, traffic reached pods before Java had finished starting, and old pods stopped while requests were still arriving.

### Kafka: a `trades` topic with 3 partitions

| Test | Result |
| --- | --- |
| 300 trades sent while the `risk` group wasn't reading | `risk` lag grew to 300, while the `reporting` group stayed at 0: each group keeps its own offsets |
| `risk` started reading again | Lag back to 0, continuing from its last offset with nothing missed or read twice |
| 4 consumers in one group, 3 partitions | One consumer was assigned 0 partitions: partitions set the maximum parallelism |
| 3 bond keys | All three hashed to partition 0, so one partition took all the traffic (a hot partition) |
| 12 bond keys, 120 trades | Spread 70 / 20 / 30 across the partitions: better, but still uneven |

With few keys, or a few very busy ones, one partition can take most of the load. Lag should be watched per partition, not just in total.

## Tech

Java 21, Spring Boot, Maven, Docker, Eclipse Temurin, Kubernetes (kind), Helm, GitHub Actions, GitHub Container Registry, Apache Kafka