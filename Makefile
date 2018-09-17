
ALL_RPI_TYPES=rpi-b rpi-b-plus rpi-2-b rpi-3-b rpi-3-b-plus

all: .date_files/rpi_image

.date_files/rpi_image: create_rpi_image.sh .date_files/rpi_base_image
	./create_rpi_image.sh && touch $@

.date_files/rpi_base_image: create_rpi_base_image.sh .date_files/rpi_builder_image
	./create_rpi_base_image.sh && touch $@

.date_files/rpi_builder_image: create_rpi_builder_image.sh
	./create_rpi_builder_image.sh && touch $@

publish:
	docker push waltplatform/rpi-stretch
	for rpi_type in $(ALL_RPI_TYPES); do \
		tag="waltplatform/$${rpi_type}-default"; \
		docker rmi $$tag 2>/dev/null || true; \
		docker tag waltplatform/rpi-stretch $$tag; \
		docker push $$tag; \
	done
