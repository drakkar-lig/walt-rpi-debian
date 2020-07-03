
ALL_RPI_TYPES=rpi-b rpi-b-plus rpi-2-b rpi-3-b rpi-3-b-plus rpi-4-b qemu-arm
DEBIAN_VERSION=buster

all: rpi_image

rpi_image:
	docker build -t "waltplatform/rpi-$(DEBIAN_VERSION)" .

publish:
	docker push waltplatform/rpi-$(DEBIAN_VERSION)
	for rpi_type in $(ALL_RPI_TYPES); do \
		tag="waltplatform/$${rpi_type}-default"; \
		docker rmi $$tag 2>/dev/null || true; \
		docker tag waltplatform/rpi-$(DEBIAN_VERSION) $$tag; \
		docker push $$tag; \
	done
