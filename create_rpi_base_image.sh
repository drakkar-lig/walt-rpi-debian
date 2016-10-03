#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"

docker run "$DOCKER_DEBIAN_RPI_BUILDER_IMAGE" tar cf - . | \
        docker import - "$DOCKER_DEBIAN_RPI_BASE_IMAGE"

