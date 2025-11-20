obj-m := sensorv1.o

BUILD_DIR       ?= $(PWD)

all:
	$(MAKE) -C $(KERNEL_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) M=$(BUILD_DIR) src=$(PWD) modules