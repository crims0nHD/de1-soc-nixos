// sevseg.c
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

#define DEVICE_NAME "sevseg"
#define CLASS_NAME  "sevsegclass"
#define MAX_WRITE_LEN 32
#define CYCLONE_V_LWFPGA_OFFSET 0xFF200000

static unsigned long phys_addr = CYCLONE_V_LWFPGA_OFFSET + 0; /* physical base address for first digit register */

static int num = 6; /* number of seven-seg digits */

static unsigned int stride = 3; /* bytes between digit registers */

static dev_t devt;
static struct cdev sev_cdev;
static struct class *sev_class;
static struct device *sev_device;
static void __iomem *iomem_base = NULL;
static struct mutex sev_lock;

static ssize_t sev_write(struct file *file, const char __user *ubuf, size_t count, loff_t *ppos)
{
    char kbuf[MAX_WRITE_LEN + 1];
    size_t to_copy = (count > MAX_WRITE_LEN) ? MAX_WRITE_LEN : count;

    if (!iomem_base) {
        pr_err("sevseg: iomem_base not mapped\n");
        return -EIO;
    }

    if (copy_from_user(kbuf, ubuf, to_copy))
        return -EFAULT;
    kbuf[to_copy] = '\0';

    mutex_lock(&sev_lock);

    /* iterate characters and write digits left-to-right to the displays */
    uint32_t seg = 0;
    for (int i = 0; i < to_copy && i < (size_t)num; ++i) {
        char c = kbuf[i];

        if (c >= '0' && c <= '9') {
            seg = seg * 16;
            seg += c - '0';
        } 
        else if (c >= 'A' && c <= 'F'){
            seg = seg * 16;
            seg += c - 'A' + 10;
        } 
    }

    pr_info("sevseg: trying to write: %d\n", seg);

    iowrite32(seg, iomem_base);

    mutex_unlock(&sev_lock);

    /* pretend we consumed everything the user wrote (POSIX-like behavior) */
    return count;
}

static int sev_open(struct inode *inode, struct file *file)
{
    return 0;
}

static int sev_release(struct inode *inode, struct file *file)
{
    return 0;
}

static const struct file_operations sev_fops = {
    .owner = THIS_MODULE,
    .write = sev_write,
    .open = sev_open,
    .release = sev_release,
};

static int __init sev_init(void)
{
    int ret;

    if (phys_addr == 0) {
        pr_err("sevseg: phys_addr module parameter is required and must be non-zero\n");
        return -EINVAL;
    }

    mutex_init(&sev_lock);

    /* allocate device number */
    ret = alloc_chrdev_region(&devt, 0, 1, DEVICE_NAME);
    if (ret) {
        pr_err("sevseg: alloc_chrdev_region failed: %d\n", ret);
        return ret;
    }

    cdev_init(&sev_cdev, &sev_fops);
    sev_cdev.owner = THIS_MODULE;
    ret = cdev_add(&sev_cdev, devt, 1);
    if (ret) {
        pr_err("sevseg: cdev_add failed: %d\n", ret);
        goto unregister_chrdev;
    }

    sev_class = class_create(THIS_MODULE, CLASS_NAME);
    if (IS_ERR(sev_class)) {
        pr_err("sevseg: class_create failed\n");
        ret = PTR_ERR(sev_class);
        goto del_cdev;
    }

    sev_device = device_create(sev_class, NULL, devt, NULL, DEVICE_NAME);
    if (IS_ERR(sev_device)) {
        pr_err("sevseg: device_create failed\n");
        ret = PTR_ERR(sev_device);
        goto destroy_class;
    }

    /* map physical memory */
    iomem_base = ioremap(phys_addr, stride * num);
    if (!iomem_base) {
        pr_err("sevseg: ioremap failed for phys_addr 0x%lx\n", phys_addr);
        ret = -EIO;
        goto destroy_device;
    }

    pr_info("sevseg: loaded. dev=/dev/%s phys=0x%lx num=%d stride=%u\n",
            DEVICE_NAME, phys_addr, num, stride);

    /* blank displays on load */
    iowrite32(0x00006969, iomem_base);
    /* max brigtness */
    iowrite32(0xFFFFFFFF, iomem_base + 4);
    /* enable */
    iowrite32(0xFFFFFFFF, iomem_base + 8);

    return 0;

destroy_device:
    device_destroy(sev_class, devt);
destroy_class:
    class_destroy(sev_class);
del_cdev:
    cdev_del(&sev_cdev);
unregister_chrdev:
    unregister_chrdev_region(devt, 1);
    return ret;
}

static void __exit sev_exit(void)
{
    if (iomem_base) {
        /* blank displays */
        int i;
        for (i = 0; i < num; ++i) {
            void __iomem *reg = iomem_base + (i * stride);
            iowrite8(0x00, reg);
        }
        iounmap(iomem_base);
    }

    device_destroy(sev_class, devt);
    class_destroy(sev_class);
    cdev_del(&sev_cdev);
    unregister_chrdev_region(devt, 1);
    pr_info("sevseg: unloaded\n");
}

module_init(sev_init);
module_exit(sev_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("david");
MODULE_DESCRIPTION("Simple sevenseg driver");
MODULE_VERSION("0.1");
