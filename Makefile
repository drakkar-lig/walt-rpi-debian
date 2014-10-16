
DOCKER_DEBIAN_RPI_IMAGE=$(shell docker run waltplatform/dev-master \
							conf-get DOCKER_DEBIAN_RPI_IMAGE)

all: .date_files/rpi_image

.date_files/rpi_image: create_rpi_image.sh .date_files/rpi_base_image
	./create_rpi_image.sh && touch $@

.date_files/rpi_base_image: create_rpi_base_image.sh .date_files/rpi_builder_image
	./create_rpi_base_image.sh && touch $@

.date_files/rpi_builder_image: create_rpi_builder_image.sh
	./create_rpi_builder_image.sh && touch $@

publish:
	docker push $(DOCKER_DEBIAN_RPI_IMAGE)
