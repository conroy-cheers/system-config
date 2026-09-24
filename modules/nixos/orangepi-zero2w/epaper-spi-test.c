// SPDX-License-Identifier: MIT
/* Minimal userspace bring-up tool for the Waveshare 2.66-inch black/white/red B panel. */

#include <errno.h>
#include <fcntl.h>
#include <linux/gpio.h>
#include <linux/spi/spidev.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define PANEL_WIDTH 152
#define PANEL_HEIGHT 296
#define PANEL_STRIDE (PANEL_WIDTH / 8)
#define PANEL_BYTES (PANEL_STRIDE * PANEL_HEIGHT)

#define GPIO_RESET 226 /* PH2 */
#define GPIO_BUSY 228  /* PH4 */
#define GPIO_DC 262    /* PI6 */

static int spi_fd;
static int reset_fd;
static int busy_fd;
static int dc_fd;

static void die(const char *message)
{
	perror(message);
	exit(EXIT_FAILURE);
}

static void sleep_ms(unsigned int milliseconds)
{
	struct timespec delay = {
		.tv_sec = milliseconds / 1000,
		.tv_nsec = (long)(milliseconds % 1000) * 1000000L,
	};

	while (nanosleep(&delay, &delay) < 0 && errno == EINTR)
		;
}

static double monotonic_seconds(void)
{
	struct timespec now;

	if (clock_gettime(CLOCK_MONOTONIC, &now) < 0)
		die("clock_gettime");
	return now.tv_sec + now.tv_nsec / 1000000000.0;
}

static int request_gpio_line(int chip_fd, unsigned int offset,
			     uint64_t flags, unsigned int initial,
			     const char *name)
{
	struct gpio_v2_line_request request = {
		.offsets = { offset },
		.config.flags = flags,
		.num_lines = 1,
	};

	strncpy(request.consumer, name, sizeof(request.consumer) - 1);
	if (flags & GPIO_V2_LINE_FLAG_OUTPUT) {
		request.config.num_attrs = 1;
		request.config.attrs[0].attr.id = GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
		request.config.attrs[0].attr.values = initial ? 1 : 0;
		request.config.attrs[0].mask = 1;
	}
	if (ioctl(chip_fd, GPIO_V2_GET_LINE_IOCTL, &request) < 0)
		die(name);
	return request.fd;
}

static void set_gpio(int fd, unsigned int value)
{
	struct gpio_v2_line_values data = {
		.bits = value ? 1 : 0,
		.mask = 1,
	};

	if (ioctl(fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &data) < 0)
		die("GPIO_V2_LINE_SET_VALUES_IOCTL");
}

static unsigned int get_gpio(int fd)
{
	struct gpio_v2_line_values data = { .mask = 1 };

	if (ioctl(fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &data) < 0)
		die("GPIO_V2_LINE_GET_VALUES_IOCTL");
	return data.bits & 1;
}

static void spi_write_all(const uint8_t *data, size_t length)
{
	while (length > 0) {
		ssize_t written = write(spi_fd, data, length > 4096 ? 4096 : length);

		if (written < 0)
			die("SPI write");
		data += written;
		length -= written;
	}
}

static void send_command(uint8_t command)
{
	set_gpio(dc_fd, 0);
	spi_write_all(&command, 1);
}

static void send_data(const uint8_t *data, size_t length)
{
	set_gpio(dc_fd, 1);
	spi_write_all(data, length);
}

static void send_byte(uint8_t value)
{
	send_data(&value, 1);
}

static void wait_ready(const char *operation)
{
	double started = monotonic_seconds();

	sleep_ms(50);
	while (get_gpio(busy_fd)) {
		if (monotonic_seconds() - started > 30.0) {
			fprintf(stderr, "%s: BUSY timeout\n", operation);
			exit(EXIT_FAILURE);
		}
		usleep(5000);
	}
	fprintf(stderr, "%s: ready after %.3f s\n", operation,
		monotonic_seconds() - started);
}

static void hardware_reset(void)
{
	set_gpio(reset_fd, 1);
	sleep_ms(200);
	set_gpio(reset_fd, 0);
	usleep(2000);
	set_gpio(reset_fd, 1);
	sleep_ms(200);
}

static void set_full_ram_area(void)
{
	static const uint8_t x_range[] = { 0, PANEL_STRIDE - 1 };
	static const uint8_t y_range[] = {
		0, 0, (PANEL_HEIGHT - 1) & 0xff, (PANEL_HEIGHT - 1) >> 8,
	};
	static const uint8_t y_start[] = { 0, 0 };

	send_command(0x44);
	send_data(x_range, sizeof(x_range));
	send_command(0x45);
	send_data(y_range, sizeof(y_range));
	send_command(0x4e);
	send_byte(0);
	send_command(0x4f);
	send_data(y_start, sizeof(y_start));
}

static void initialize_panel(void)
{
	static const uint8_t update_control[] = { 0x00, 0x80 };

	hardware_reset();
	send_command(0x12);
	sleep_ms(30);
	wait_ready("software reset");

	send_command(0x11);
	send_byte(0x03);
	set_full_ram_area();
	send_command(0x21);
	send_data(update_control, sizeof(update_control));
	set_full_ram_area();
}

static void write_ram(uint8_t command, const uint8_t *image)
{
	set_full_ram_area();
	send_command(command);
	send_data(image, PANEL_BYTES);
}

static void refresh_panel(void)
{
	send_command(0x20);
	wait_ready("full refresh");
}

static void make_pattern(uint8_t *black, uint8_t *red, const char *pattern)
{
	unsigned int x, y;

	memset(black, 0xff, PANEL_BYTES);
	memset(red, 0xff, PANEL_BYTES);
	if (!strcmp(pattern, "white")) {
		return;
	}
	if (!strcmp(pattern, "black")) {
		memset(black, 0x00, PANEL_BYTES);
		return;
	}
	if (!strcmp(pattern, "red")) {
		memset(red, 0x00, PANEL_BYTES);
		return;
	}
	if (strcmp(pattern, "tricolor")) {
		fprintf(stderr, "pattern must be white, black, red, or tricolor\n");
		exit(EXIT_FAILURE);
	}

	for (y = 0; y < PANEL_HEIGHT; y++) {
		for (x = 0; x < PANEL_WIDTH; x++) {
			uint8_t mask = 0x80 >> (x % 8);
			unsigned int offset = y * PANEL_STRIDE + x / 8;

			if (x < PANEL_WIDTH / 3)
				black[offset] &= ~mask;
			else if (x >= 2 * PANEL_WIDTH / 3)
				red[offset] &= ~mask;
		}
	}
}

int main(int argc, char **argv)
{
	uint8_t black[PANEL_BYTES];
	uint8_t red[PANEL_BYTES];
	uint32_t speed = 4000000;
	uint8_t mode = SPI_MODE_0;
	uint8_t bits = 8;
	int gpiochip_fd;
	const char *pattern = argc == 2 ? argv[1] : "tricolor";

	spi_fd = open("/dev/spidev1.0", O_RDWR);
	if (spi_fd < 0)
		die("open /dev/spidev1.0");
	if (ioctl(spi_fd, SPI_IOC_WR_MODE, &mode) < 0 ||
	    ioctl(spi_fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
	    ioctl(spi_fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0)
		die("configure SPI");

	gpiochip_fd = open("/dev/gpiochip1", O_RDONLY);
	if (gpiochip_fd < 0)
		die("open /dev/gpiochip1");
	reset_fd = request_gpio_line(gpiochip_fd, GPIO_RESET,
		GPIO_V2_LINE_FLAG_OUTPUT, 1, "epaper-reset");
	dc_fd = request_gpio_line(gpiochip_fd, GPIO_DC,
		GPIO_V2_LINE_FLAG_OUTPUT, 0, "epaper-dc");
	busy_fd = request_gpio_line(gpiochip_fd, GPIO_BUSY,
		GPIO_V2_LINE_FLAG_INPUT, 0, "epaper-busy");
	close(gpiochip_fd);

	make_pattern(black, red, pattern);
	for (size_t i = 0; i < sizeof(red); i++)
		red[i] = ~red[i];
	initialize_panel();
	write_ram(0x24, black);
	write_ram(0x26, red);
	refresh_panel();
	send_command(0x10);
	send_byte(0x01);
	fprintf(stderr, "displayed %s pattern\n", pattern);
	return EXIT_SUCCESS;
}
