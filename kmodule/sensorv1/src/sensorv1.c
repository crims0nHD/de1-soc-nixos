// sensorv1.c
#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/mutex.h>
#include <linux/moduleparam.h>

#define DEVICE_NAME "hdc1000"
#define CLASS_NAME  "ssldriverclass"
#define CYCLONE_V_LWFPGA_OFFSET 0xFF200000
#define DEVICE_OFFSET 0x400
#define DEVICE_LENGTH 0x40
#define MAX_STR_LENGTH_OUTPUT 120

static unsigned long phys_addr = CYCLONE_V_LWFPGA_OFFSET + 0 + DEVICE_OFFSET;

static size_t const OFFSET_REGISTER_CTRL = 0x0;
static size_t const OFFSET_REGISTER_SAMPLE = 0x10;
static size_t const OFFSET_REGISTER_STATUS = 0x1C;

static size_t const OFFSET_REGISTER_SAMPLE_SENSOR_TEMP = 0x0;
static size_t const OFFSET_REGISTER_SAMPLE_SENSOR_HUM = 0x4;
static size_t const OFFSET_REGISTER_SAMPLE_TIMESTAMP = 0x8;

static dev_t devt;
static struct cdev ssldriver_cdev;
static struct class *ssldriver_class;
static struct device *ssldriver_device;
static void __iomem *iomem_base = NULL;
static struct mutex ssldriver_lock;

static inline unsigned int swap_endian_u32(unsigned int x)
{
    return ((x & 0x000000FFU) << 24) |
           ((x & 0x0000FF00U) << 8)  |
           ((x & 0x00FF0000U) >> 8)  |
           ((x & 0xFF000000U) >> 24);
}

static ssize_t ssldriver_read(struct file *filp, char __user *buf, size_t count, loff_t *ppos)
{
    // Check if sensor has data
    unsigned int status_reg = ioread32(iomem_base + OFFSET_REGISTER_STATUS);
    if ((status_reg & 0b1) == 0) {
        return 0;
    }

    // Get sensor values and timestamp
    // This will pop hardware fifo
    unsigned int temp_reg = ioread32(iomem_base + OFFSET_REGISTER_SAMPLE + OFFSET_REGISTER_SAMPLE_SENSOR_TEMP);
    unsigned int hum_reg = ioread32(iomem_base + OFFSET_REGISTER_SAMPLE + OFFSET_REGISTER_SAMPLE_SENSOR_HUM);
    unsigned int timestamp_reg = ioread32(iomem_base + OFFSET_REGISTER_SAMPLE + OFFSET_REGISTER_SAMPLE_TIMESTAMP);

    // Convert endianness
    unsigned int temp_val = swap_endian_u32(temp_reg);
    unsigned int hum_val = swap_endian_u32(hum_reg);
    unsigned int timestamp_val = swap_endian_u32(timestamp_reg);


    // Format string
    char* s = kmalloc(128, GFP_KERNEL);
    if (!s)
        return -ENOMEM;

    /* format a string into the allocated buffer */
    size_t len = sprintf(s, "%X;%X;%X\n", timestamp_val, temp_val, hum_val);

    size_t len_to_copy = len < count ? len : count;

    if (copy_to_user(buf, s, len_to_copy))
        return -EFAULT;

    kfree(s);

    return len_to_copy;
}

static int ssldriver_open(struct inode *inode, struct file *file)
{
    // Enable
    iowrite32(0x1, iomem_base + OFFSET_REGISTER_CTRL);
    return 0;
}

static int ssldriver_release(struct inode *inode, struct file *file)
{
    return 0;
}

static const struct file_operations ssldriver_fops = {
    .owner = THIS_MODULE,
    .read = ssldriver_read,
    .open = ssldriver_open,
    .release = ssldriver_release,
};

static int __init ssldriver_init(void)
{
    int ret;

    if (phys_addr == 0) {
        pr_err("ssldriver: phys_addr module parameter is required and must be non-zero\n");
        return -EINVAL;
    }

    mutex_init(&ssldriver_lock);

    /* allocate device number */
    ret = alloc_chrdev_region(&devt, 0, 1, DEVICE_NAME);
    if (ret) {
        pr_err("ssldriver: alloc_chrdev_region failed: %d\n", ret);
        return ret;
    }

    cdev_init(&ssldriver_cdev, &ssldriver_fops);
    ssldriver_cdev.owner = THIS_MODULE;
    ret = cdev_add(&ssldriver_cdev, devt, 1);
    if (ret) {
        pr_err("ssldriver: cdev_add failed: %d\n", ret);
        goto unregister_chrdev;
    }

    ssldriver_class = class_create(THIS_MODULE, CLASS_NAME);
    if (IS_ERR(ssldriver_class)) {
        pr_err("ssldriver: class_create failed\n");
        ret = PTR_ERR(ssldriver_class);
        goto del_cdev;
    }

    ssldriver_device = device_create(ssldriver_class, NULL, devt, NULL, DEVICE_NAME);
    if (IS_ERR(ssldriver_device)) {
        pr_err("ssldriver: device_create failed\n");
        ret = PTR_ERR(ssldriver_device);
        goto destroy_class;
    }

    /* map physical memory */
    iomem_base = ioremap(phys_addr, DEVICE_LENGTH);
    if (!iomem_base) {
        pr_err("ssldriver: ioremap failed for phys_addr 0x%lx\n", phys_addr);
        ret = -EIO;
        goto destroy_device;
    }

    pr_info("ssldriver: loaded. dev=/dev/%s \n",
            DEVICE_NAME);

    return 0;

destroy_device:
    device_destroy(ssldriver_class, devt);
destroy_class:
    class_destroy(ssldriver_class);
del_cdev:
    cdev_del(&ssldriver_cdev);
unregister_chrdev:
    unregister_chrdev_region(devt, 1);
    return ret;
}

static void __exit ssldriver_exit(void)
{
    device_destroy(ssldriver_class, devt);
    class_destroy(ssldriver_class);
    cdev_del(&ssldriver_cdev);
    unregister_chrdev_region(devt, 1);
    pr_info("ssldriver: unloaded\n");
}

module_init(ssldriver_init);
module_exit(ssldriver_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("david");
MODULE_DESCRIPTION("Last minute implementation cause rust didnt work");
MODULE_VERSION("0.1");
