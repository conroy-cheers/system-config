// SPDX-License-Identifier: GPL-2.0-only
/*
 * DRM driver for the Waveshare 2.66-inch black/white/red e-paper module.
 *
 * The controller sequence follows Waveshare's EPD_2in66b reference driver:
 * https://github.com/waveshareteam/e-Paper/tree/master/RaspberryPi_JetsonNano/c/lib/e-Paper/EPD_2in66b.c
 * The DRM structure was adapted from Devarsh Thakkar's SSD16xx proposal and
 * reduced to the hardware and waveform that have been validated on shrimpus.
 *
 * Copyright (C) 2026 Texas Instruments Incorporated
 * Copyright (C) 2026 Conroy Cheers
 */

#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/property.h>
#include <linux/spi/spi.h>

#include <drm/drm_atomic_helper.h>
#include <drm/drm_drv.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_framebuffer.h>
#include <drm/drm_gem_atomic_helper.h>
#include <drm/drm_gem_dma_helper.h>
#include <drm/drm_gem_framebuffer_helper.h>
#include <drm/drm_modes.h>
#include <drm/drm_probe_helper.h>
#include <drm/drm_print.h>
#include <drm/drm_simple_kms_helper.h>

#define SSD16XX_WIDTH		152
#define SSD16XX_HEIGHT		296
#define SSD16XX_STRIDE		(SSD16XX_WIDTH / 8)
#define SSD16XX_FRAME_BYTES	(SSD16XX_STRIDE * SSD16XX_HEIGHT)
#define SSD16XX_BUSY_TIMEOUT_MS	30000
#define SSD16XX_AUTOSUSPEND_MS	1000

#define SSD16XX_CMD_DEEP_SLEEP		0x10
#define SSD16XX_CMD_DATA_ENTRY_MODE	0x11
#define SSD16XX_CMD_SW_RESET		0x12
#define SSD16XX_CMD_MASTER_ACTIVATION	0x20
#define SSD16XX_CMD_UPDATE_CONTROL1	0x21
#define SSD16XX_CMD_WRITE_RAM_BW		0x24
#define SSD16XX_CMD_WRITE_RAM_RED	0x26
#define SSD16XX_CMD_RAM_X_WINDOW		0x44
#define SSD16XX_CMD_RAM_Y_WINDOW		0x45
#define SSD16XX_CMD_RAM_X_COUNTER	0x4e
#define SSD16XX_CMD_RAM_Y_COUNTER	0x4f

struct ssd16xx_panel {
	struct drm_device drm;
	struct drm_simple_display_pipe pipe;
	struct drm_connector connector;
	struct spi_device *spi;
	struct gpio_desc *reset;
	struct gpio_desc *busy;
	struct gpio_desc *dc;
	struct completion ready;
	u8 *black;
	u8 *red;
	u32 rotation;
	bool initialized;
};

static inline struct ssd16xx_panel *to_ssd16xx(struct drm_device *drm)
{
	return container_of(drm, struct ssd16xx_panel, drm);
}

static int ssd16xx_command(struct ssd16xx_panel *panel, u8 command)
{
	gpiod_set_value_cansleep(panel->dc, 0);
	return spi_write(panel->spi, &command, sizeof(command));
}

static int ssd16xx_data(struct ssd16xx_panel *panel, const void *data,
			size_t length)
{
	gpiod_set_value_cansleep(panel->dc, 1);
	return spi_write(panel->spi, data, length);
}

static int ssd16xx_byte(struct ssd16xx_panel *panel, u8 value)
{
	return ssd16xx_data(panel, &value, sizeof(value));
}

static irqreturn_t ssd16xx_busy_irq(int irq, void *data)
{
	struct ssd16xx_panel *panel = data;

	complete(&panel->ready);
	return IRQ_HANDLED;
}

static int ssd16xx_wait_ready(struct ssd16xx_panel *panel)
{
	unsigned long timeout;
	int busy;

	busy = gpiod_get_value_cansleep(panel->busy);
	if (busy < 0)
		return busy;
	if (!busy)
		return 0;

	timeout = wait_for_completion_timeout(&panel->ready,
					      msecs_to_jiffies(SSD16XX_BUSY_TIMEOUT_MS));
	if (!timeout)
		return -ETIMEDOUT;

	busy = gpiod_get_value_cansleep(panel->busy);
	if (busy < 0)
		return busy;
	return busy ? -EIO : 0;
}

static void ssd16xx_reset(struct ssd16xx_panel *panel)
{
	/* RESET is active low in DT, so logical 1 asserts it. */
	gpiod_set_value_cansleep(panel->reset, 0);
	msleep(200);
	gpiod_set_value_cansleep(panel->reset, 1);
	usleep_range(2000, 3000);
	gpiod_set_value_cansleep(panel->reset, 0);
	msleep(200);
}

static int ssd16xx_set_full_ram(struct ssd16xx_panel *panel)
{
	static const u8 x_window[] = { 0, SSD16XX_STRIDE - 1 };
	static const u8 y_window[] = {
		0, 0, (SSD16XX_HEIGHT - 1) & 0xff, (SSD16XX_HEIGHT - 1) >> 8,
	};
	static const u8 y_start[] = { 0, 0 };
	int ret;

	ret = ssd16xx_command(panel, SSD16XX_CMD_RAM_X_WINDOW);
	if (ret)
		return ret;
	ret = ssd16xx_data(panel, x_window, sizeof(x_window));
	if (ret)
		return ret;
	ret = ssd16xx_command(panel, SSD16XX_CMD_RAM_Y_WINDOW);
	if (ret)
		return ret;
	ret = ssd16xx_data(panel, y_window, sizeof(y_window));
	if (ret)
		return ret;
	ret = ssd16xx_command(panel, SSD16XX_CMD_RAM_X_COUNTER);
	if (ret)
		return ret;
	ret = ssd16xx_byte(panel, 0);
	if (ret)
		return ret;
	ret = ssd16xx_command(panel, SSD16XX_CMD_RAM_Y_COUNTER);
	if (ret)
		return ret;
	return ssd16xx_data(panel, y_start, sizeof(y_start));
}

static int ssd16xx_initialize(struct ssd16xx_panel *panel)
{
	static const u8 update_control[] = { 0x00, 0x80 };
	int ret;

	ssd16xx_reset(panel);
	reinit_completion(&panel->ready);
	ret = ssd16xx_command(panel, SSD16XX_CMD_SW_RESET);
	if (ret)
		return ret;
	msleep(30);
	ret = ssd16xx_wait_ready(panel);
	if (ret)
		return ret;

	ret = ssd16xx_command(panel, SSD16XX_CMD_DATA_ENTRY_MODE);
	if (ret)
		return ret;
	ret = ssd16xx_byte(panel, 0x03);
	if (ret)
		return ret;
	ret = ssd16xx_set_full_ram(panel);
	if (ret)
		return ret;
	ret = ssd16xx_command(panel, SSD16XX_CMD_UPDATE_CONTROL1);
	if (ret)
		return ret;
	ret = ssd16xx_data(panel, update_control, sizeof(update_control));
	if (!ret)
		panel->initialized = true;
	return ret;
}

static void ssd16xx_map_pixel(const struct ssd16xx_panel *panel,
			      unsigned int physical_x,
			      unsigned int physical_y,
			      unsigned int *source_x,
			      unsigned int *source_y)
{
	switch (panel->rotation) {
	case 90:
		*source_x = SSD16XX_HEIGHT - 1 - physical_y;
		*source_y = physical_x;
		break;
	case 180:
		*source_x = SSD16XX_WIDTH - 1 - physical_x;
		*source_y = SSD16XX_HEIGHT - 1 - physical_y;
		break;
	case 270:
		*source_x = physical_y;
		*source_y = SSD16XX_WIDTH - 1 - physical_x;
		break;
	default:
		*source_x = physical_x;
		*source_y = physical_y;
		break;
	}
}

static void ssd16xx_read_rgb(const struct iosys_map *map,
			     const struct drm_framebuffer *fb,
			     unsigned int x, unsigned int y,
			     u8 *red, u8 *green, u8 *blue)
{
	size_t offset = (size_t)y * fb->pitches[0];

	switch (fb->format->format) {
	case DRM_FORMAT_XRGB8888: {
		u32 pixel = iosys_map_rd(map, offset + x * sizeof(pixel), u32);

		*red = (pixel >> 16) & 0xff;
		*green = (pixel >> 8) & 0xff;
		*blue = pixel & 0xff;
		break;
	}
	case DRM_FORMAT_RGB565: {
		u16 pixel = iosys_map_rd(map, offset + x * sizeof(pixel), u16);

		*red = ((pixel >> 11) & 0x1f) * 255 / 31;
		*green = ((pixel >> 5) & 0x3f) * 255 / 63;
		*blue = (pixel & 0x1f) * 255 / 31;
		break;
	}
	default: {
		u8 pixel = iosys_map_rd(map, offset + x / 8, u8);
		u8 value = pixel & BIT(7 - (x % 8)) ? 255 : 0;

		*red = value;
		*green = value;
		*blue = value;
		break;
	}
	}
}

static void ssd16xx_convert(struct ssd16xx_panel *panel,
			    const struct iosys_map *map,
			    const struct drm_framebuffer *fb)
{
	unsigned int physical_x, physical_y;
	unsigned int source_x, source_y;

	memset(panel->black, 0, SSD16XX_FRAME_BYTES);
	memset(panel->red, 0, SSD16XX_FRAME_BYTES);

	for (physical_y = 0; physical_y < SSD16XX_HEIGHT; physical_y++) {
		for (physical_x = 0; physical_x < SSD16XX_WIDTH; physical_x++) {
			size_t output = physical_y * SSD16XX_STRIDE + physical_x / 8;
			u8 mask = BIT(7 - (physical_x % 8));
			u8 r, g, b;
			u16 luma;

			ssd16xx_map_pixel(panel, physical_x, physical_y,
					  &source_x, &source_y);
			ssd16xx_read_rgb(map, fb, source_x, source_y, &r, &g, &b);
			luma = (77 * r + 150 * g + 29 * b) >> 8;

			if (r > 127 && r > g && r > b) {
				panel->black[output] |= mask;
				panel->red[output] |= mask;
			} else if (luma > 127) {
				panel->black[output] |= mask;
			}
		}
	}
}

static int ssd16xx_write_plane(struct ssd16xx_panel *panel, u8 command,
			       const u8 *data)
{
	int ret;

	ret = ssd16xx_set_full_ram(panel);
	if (ret)
		return ret;
	ret = ssd16xx_command(panel, command);
	if (ret)
		return ret;
	return ssd16xx_data(panel, data, SSD16XX_FRAME_BYTES);
}

static int ssd16xx_refresh(struct ssd16xx_panel *panel)
{
	int ret;

	ret = ssd16xx_write_plane(panel, SSD16XX_CMD_WRITE_RAM_BW,
				  panel->black);
	if (ret)
		return ret;
	ret = ssd16xx_write_plane(panel, SSD16XX_CMD_WRITE_RAM_RED,
				  panel->red);
	if (ret)
		return ret;

	reinit_completion(&panel->ready);
	ret = ssd16xx_command(panel, SSD16XX_CMD_MASTER_ACTIVATION);
	if (ret)
		return ret;
	return ssd16xx_wait_ready(panel);
}

static void ssd16xx_pipe_enable(struct drm_simple_display_pipe *pipe,
				struct drm_crtc_state *crtc_state,
				struct drm_plane_state *plane_state)
{
	struct ssd16xx_panel *panel = to_ssd16xx(pipe->crtc.dev);
	int ret;

	ret = pm_runtime_resume_and_get(panel->drm.dev);
	if (ret < 0) {
		drm_err(&panel->drm, "could not initialize panel: %d\n", ret);
	} else {
		pm_runtime_mark_last_busy(panel->drm.dev);
		pm_runtime_put_autosuspend(panel->drm.dev);
	}
}

static void ssd16xx_pipe_update(struct drm_simple_display_pipe *pipe,
				struct drm_plane_state *old_state)
{
	struct ssd16xx_panel *panel = to_ssd16xx(pipe->crtc.dev);
	struct drm_plane_state *state = pipe->plane.state;
	struct drm_shadow_plane_state *shadow = to_drm_shadow_plane_state(state);
	struct drm_framebuffer *fb = state->fb;
	int ret;

	if (!fb)
		return;

	ret = pm_runtime_resume_and_get(panel->drm.dev);
	if (ret < 0) {
		drm_err(&panel->drm, "could not wake panel: %d\n", ret);
		return;
	}

	ret = drm_gem_fb_begin_cpu_access(fb, DMA_FROM_DEVICE);
	if (ret) {
		drm_err(&panel->drm, "could not access framebuffer: %d\n", ret);
		goto out_pm;
	}

	ssd16xx_convert(panel, &shadow->data[0], fb);
	drm_gem_fb_end_cpu_access(fb, DMA_FROM_DEVICE);

	ret = ssd16xx_refresh(panel);
	if (ret)
		drm_err(&panel->drm, "display refresh failed: %d\n", ret);

out_pm:
	pm_runtime_mark_last_busy(panel->drm.dev);
	pm_runtime_put_autosuspend(panel->drm.dev);
}

static const struct drm_simple_display_pipe_funcs ssd16xx_pipe_funcs = {
	.enable = ssd16xx_pipe_enable,
	.update = ssd16xx_pipe_update,
	DRM_GEM_SIMPLE_DISPLAY_PIPE_SHADOW_PLANE_FUNCS,
};

static int ssd16xx_connector_get_modes(struct drm_connector *connector)
{
	struct ssd16xx_panel *panel = to_ssd16xx(connector->dev);
	struct drm_display_mode *mode;

	mode = drm_mode_create(connector->dev);
	if (!mode)
		return 0;

	if (panel->rotation == 90 || panel->rotation == 270) {
		mode->hdisplay = SSD16XX_HEIGHT;
		mode->vdisplay = SSD16XX_WIDTH;
		mode->width_mm = 60;
		mode->height_mm = 31;
	} else {
		mode->hdisplay = SSD16XX_WIDTH;
		mode->vdisplay = SSD16XX_HEIGHT;
		mode->width_mm = 31;
		mode->height_mm = 60;
	}
	mode->hsync_start = mode->hdisplay;
	mode->hsync_end = mode->hdisplay;
	mode->htotal = mode->hdisplay;
	mode->vsync_start = mode->vdisplay;
	mode->vsync_end = mode->vdisplay;
	mode->vtotal = mode->vdisplay;
	mode->clock = mode->hdisplay * mode->vdisplay * 60 / 1000;
	mode->type = DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED;
	drm_mode_set_name(mode);
	drm_mode_probed_add(connector, mode);
	return 1;
}

static const struct drm_connector_helper_funcs ssd16xx_connector_helper_funcs = {
	.get_modes = ssd16xx_connector_get_modes,
};

static const struct drm_connector_funcs ssd16xx_connector_funcs = {
	.reset = drm_atomic_helper_connector_reset,
	.fill_modes = drm_helper_probe_single_connector_modes,
	.destroy = drm_connector_cleanup,
	.atomic_duplicate_state = drm_atomic_helper_connector_duplicate_state,
	.atomic_destroy_state = drm_atomic_helper_connector_destroy_state,
};

static const u32 ssd16xx_formats[] = {
	DRM_FORMAT_XRGB8888,
	DRM_FORMAT_RGB565,
	DRM_FORMAT_R1,
};

DEFINE_DRM_GEM_FOPS(ssd16xx_fops);

static const struct drm_driver ssd16xx_drm_driver = {
	.driver_features = DRIVER_GEM | DRIVER_MODESET | DRIVER_ATOMIC,
	.fops = &ssd16xx_fops,
	.name = "ssd16xx",
	.desc = "Waveshare 2.66-inch B e-paper panel",
	.major = 1,
	.minor = 0,
	DRM_GEM_DMA_DRIVER_OPS_VMAP,
};

static const struct drm_mode_config_funcs ssd16xx_mode_config_funcs = {
	.fb_create = drm_gem_fb_create,
	.atomic_check = drm_atomic_helper_check,
	.atomic_commit = drm_atomic_helper_commit,
};

static const struct drm_mode_config_helper_funcs ssd16xx_mode_config_helpers = {
	.atomic_commit_tail = drm_atomic_helper_commit_tail_rpm,
};

static int ssd16xx_runtime_suspend(struct device *dev)
{
	struct ssd16xx_panel *panel = to_ssd16xx(dev_get_drvdata(dev));
	int ret;

	if (!panel->initialized)
		return 0;
	ret = ssd16xx_command(panel, SSD16XX_CMD_DEEP_SLEEP);
	if (!ret)
		ret = ssd16xx_byte(panel, 0x01);
	panel->initialized = false;
	return ret;
}

static int ssd16xx_runtime_resume(struct device *dev)
{
	struct ssd16xx_panel *panel = to_ssd16xx(dev_get_drvdata(dev));

	if (panel->initialized)
		return 0;
	return ssd16xx_initialize(panel);
}

static int ssd16xx_suspend(struct device *dev)
{
	struct drm_device *drm = dev_get_drvdata(dev);
	int ret;

	ret = drm_mode_config_helper_suspend(drm);
	if (ret)
		return ret;
	ret = pm_runtime_force_suspend(dev);
	if (ret)
		drm_mode_config_helper_resume(drm);
	return ret;
}

static int ssd16xx_resume(struct device *dev)
{
	struct drm_device *drm = dev_get_drvdata(dev);
	int ret;

	ret = pm_runtime_force_resume(dev);
	if (ret)
		return ret;
	return drm_mode_config_helper_resume(drm);
}

static const struct dev_pm_ops ssd16xx_pm_ops = {
	SYSTEM_SLEEP_PM_OPS(ssd16xx_suspend, ssd16xx_resume)
	RUNTIME_PM_OPS(ssd16xx_runtime_suspend, ssd16xx_runtime_resume, NULL)
};

static int ssd16xx_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct ssd16xx_panel *panel;
	struct drm_device *drm;
	u32 logical_width, logical_height;
	int irq, ret;

	if (!dev->coherent_dma_mask) {
		ret = dma_coerce_mask_and_coherent(dev, DMA_BIT_MASK(64));
		if (ret)
			return dev_err_probe(dev, ret, "could not set DMA mask\n");
	}

	panel = devm_drm_dev_alloc(dev, &ssd16xx_drm_driver,
				   struct ssd16xx_panel, drm);
	if (IS_ERR(panel))
		return PTR_ERR(panel);

	drm = &panel->drm;
	panel->spi = spi;
	spi_set_drvdata(spi, drm);
	init_completion(&panel->ready);

	ret = device_property_read_u32(dev, "rotation", &panel->rotation);
	if (ret)
		panel->rotation = 0;
	if (panel->rotation != 0 && panel->rotation != 90 &&
	    panel->rotation != 180 && panel->rotation != 270)
		return dev_err_probe(dev, -EINVAL, "invalid rotation %u\n",
				     panel->rotation);

	panel->reset = devm_gpiod_get(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(panel->reset))
		return dev_err_probe(dev, PTR_ERR(panel->reset),
				     "could not get RESET GPIO\n");
	panel->busy = devm_gpiod_get(dev, "busy", GPIOD_IN);
	if (IS_ERR(panel->busy))
		return dev_err_probe(dev, PTR_ERR(panel->busy),
				     "could not get BUSY GPIO\n");
	panel->dc = devm_gpiod_get(dev, "dc", GPIOD_OUT_LOW);
	if (IS_ERR(panel->dc))
		return dev_err_probe(dev, PTR_ERR(panel->dc),
				     "could not get D/C GPIO\n");

	irq = gpiod_to_irq(panel->busy);
	if (irq < 0)
		return dev_err_probe(dev, irq, "could not map BUSY interrupt\n");
	ret = devm_request_irq(dev, irq, ssd16xx_busy_irq, IRQF_TRIGGER_FALLING,
			       dev_name(dev), panel);
	if (ret)
		return dev_err_probe(dev, ret, "could not request BUSY interrupt\n");

	panel->black = devm_kmalloc(dev, SSD16XX_FRAME_BYTES, GFP_KERNEL);
	panel->red = devm_kmalloc(dev, SSD16XX_FRAME_BYTES, GFP_KERNEL);
	if (!panel->black || !panel->red)
		return -ENOMEM;

	spi->mode = SPI_MODE_0;
	spi->bits_per_word = 8;
	ret = spi_setup(spi);
	if (ret)
		return dev_err_probe(dev, ret, "could not configure SPI\n");

	ret = drmm_mode_config_init(drm);
	if (ret)
		return ret;
	drm->mode_config.funcs = &ssd16xx_mode_config_funcs;
	drm->mode_config.helper_private = &ssd16xx_mode_config_helpers;

	logical_width = (panel->rotation == 90 || panel->rotation == 270) ?
		SSD16XX_HEIGHT : SSD16XX_WIDTH;
	logical_height = (panel->rotation == 90 || panel->rotation == 270) ?
		SSD16XX_WIDTH : SSD16XX_HEIGHT;
	drm->mode_config.min_width = logical_width;
	drm->mode_config.max_width = logical_width;
	drm->mode_config.min_height = logical_height;
	drm->mode_config.max_height = logical_height;

	ret = drm_connector_init(drm, &panel->connector,
				 &ssd16xx_connector_funcs, DRM_MODE_CONNECTOR_SPI);
	if (ret)
		return ret;
	drm_connector_helper_add(&panel->connector,
				 &ssd16xx_connector_helper_funcs);
	panel->connector.display_info.width_mm =
		logical_width == SSD16XX_HEIGHT ? 60 : 31;
	panel->connector.display_info.height_mm =
		logical_height == SSD16XX_HEIGHT ? 60 : 31;

	ret = drm_simple_display_pipe_init(drm, &panel->pipe,
					   &ssd16xx_pipe_funcs,
					   ssd16xx_formats,
					   ARRAY_SIZE(ssd16xx_formats),
					   NULL, &panel->connector);
	if (ret)
		return ret;
	drm_plane_enable_fb_damage_clips(&panel->pipe.plane);
	drm_mode_config_reset(drm);

	pm_runtime_set_suspended(dev);
	pm_runtime_set_autosuspend_delay(dev, SSD16XX_AUTOSUSPEND_MS);
	pm_runtime_use_autosuspend(dev);
	pm_runtime_enable(dev);

	ret = drm_dev_register(drm, 0);
	if (ret) {
		pm_runtime_disable(dev);
		return ret;
	}

	dev_info(dev, "registered %ux%u e-paper panel at %u degrees\n",
		 logical_width, logical_height, panel->rotation);
	return 0;
}

static void ssd16xx_remove(struct spi_device *spi)
{
	struct drm_device *drm = spi_get_drvdata(spi);

	drm_dev_unplug(drm);
	drm_atomic_helper_shutdown(drm);
	pm_runtime_disable(&spi->dev);
}

static void ssd16xx_shutdown(struct spi_device *spi)
{
	drm_atomic_helper_shutdown(spi_get_drvdata(spi));
}

static const struct of_device_id ssd16xx_of_match[] = {
	{ .compatible = "waveshare,epd-2in66b" },
	{ }
};
MODULE_DEVICE_TABLE(of, ssd16xx_of_match);

static const struct spi_device_id ssd16xx_ids[] = {
	{ "epd-2in66b" },
	{ }
};
MODULE_DEVICE_TABLE(spi, ssd16xx_ids);

static struct spi_driver ssd16xx_spi_driver = {
	.driver = {
		.name = "panel-ssd16xx",
		.of_match_table = ssd16xx_of_match,
		.pm = pm_ptr(&ssd16xx_pm_ops),
	},
	.probe = ssd16xx_probe,
	.remove = ssd16xx_remove,
	.shutdown = ssd16xx_shutdown,
	.id_table = ssd16xx_ids,
};
module_spi_driver(ssd16xx_spi_driver);

MODULE_AUTHOR("Conroy Cheers");
MODULE_DESCRIPTION("DRM driver for the Waveshare 2.66-inch B e-paper panel");
MODULE_LICENSE("GPL");
MODULE_IMPORT_NS("DMA_BUF");
