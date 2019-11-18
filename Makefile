
ALL_RPI_TYPES=rpi-b rpi-b-plus rpi-2-b rpi-3-b rpi-3-b-plus

all: rpi_image

rpi_image:
	docker build -t "waltplatform/rpi-stretch" .

publish:
	docker push waltplatform/rpi-stretch
	for rpi_type in $(ALL_RPI_TYPES); do \
		tag="waltplatform/$${rpi_type}-default"; \
		docker rmi $$tag 2>/dev/null || true; \
		docker tag waltplatform/rpi-stretch $$tag; \
		docker push $$tag; \
	done
