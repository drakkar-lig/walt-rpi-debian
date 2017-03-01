
DOCKER_DEBIAN_RPI_IMAGE=$(shell docker run waltplatform/dev-master \
							conf-get DOCKER_DEBIAN_RPI_IMAGE)
ALL_RPI_TYPES=$(shell docker run waltplatform/dev-master \
                            conf-get ALL_RPI_TYPES)
DOCKER_USER=$(shell docker run waltplatform/dev-master \
                            conf-get DOCKER_USER)

all: .date_files/rpi_image

.date_files/rpi_image: create_rpi_image.sh .date_files/rpi_base_image
	./create_rpi_image.sh && touch $@

.date_files/rpi_base_image: create_rpi_base_image.sh .date_files/rpi_builder_image
	./create_rpi_base_image.sh && touch $@

.date_files/rpi_builder_image: create_rpi_builder_image.sh
	./create_rpi_builder_image.sh && touch $@

publish:
	docker push $(DOCKER_DEBIAN_RPI_IMAGE)
	for rpi_type in $(ALL_RPI_TYPES); do \
		tag="$(DOCKER_USER)/walt-node:$${rpi_type}-default"; \
		docker rmi $$tag 2>/dev/null || true; \
		docker tag $(DOCKER_DEBIAN_RPI_IMAGE) $$tag; \
		docker push $$tag; \
	done
