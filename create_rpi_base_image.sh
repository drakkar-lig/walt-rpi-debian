#!/bin/bash
docker run "waltplatform/rpi-debian-builder" tar cf - . | \
        docker import - "waltplatform/rpi-debian-base"

