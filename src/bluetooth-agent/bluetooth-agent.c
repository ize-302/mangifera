// BlueZ pairing agent for the Quickshell launcher (BluetoothAgent.qml).
// Requests go out as JSON lines on stdout:
//
//   {"id": 3, "type": "confirm", "device": "Pixel 8", "passkey": "123456"}
//
// Types: confirm, authorize, pin, passkey, service, display-pin and
// display-passkey (no answer needed), cancel.
// Answers come in on stdin: "<id> yes [value]" or "<id> no".
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/epoll.h>
#include <unistd.h>

#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>

#define BUS_NAME "org.bluez"
#define AGENT_PATH "/org/quickshell/bluetooth_agent"
#define CAPABILITY "KeyboardDisplay"

static sd_bus *bus;

// Pending requests by id
struct pending {
	unsigned id;
	const char *type;
	sd_bus_message *call;
	struct pending *next;
};

static struct pending *pending;
static unsigned next_id;

static void put_json(const char *s)
{
	putchar('"');
	for (; *s; s++) {
		unsigned char c = *s;
		if (c == '"' || c == '\\')
			printf("\\%c", c);
		else if (c < 0x20)
			printf("\\u%04x", c);
		else
			putchar(c);
	}
	putchar('"');
}

// Name, else address; caller frees
static char *device_name(const char *path)
{
	char *alias = NULL;
	if (sd_bus_get_property_string(bus, BUS_NAME, path, "org.bluez.Device1", "Alias", NULL, &alias) >= 0)
		return alias;

	const char *address = strstr(path, "dev_");
	char *name = strdup(address ? address + 4 : path);
	for (char *c = name; *c; c++)
		if (*c == '_')
			*c = ':';
	return name;
}

static int trusted(const char *path)
{
	int value = 0;
	if (sd_bus_get_property_trivial(bus, BUS_NAME, path, "org.bluez.Device1", "Trusted", NULL, 'b', &value) < 0)
		return 0;
	return value;
}

static void send(unsigned id, const char *type, const char *path, const char *passkey, int entered)
{
	printf("{\"id\": %u, \"type\": ", id);
	put_json(type);
	if (path) {
		char *name = device_name(path);
		printf(", \"device\": ");
		put_json(name);
		free(name);
	}
	if (passkey) {
		printf(", \"passkey\": ");
		put_json(passkey);
	}
	if (entered >= 0)
		printf(", \"entered\": %d", entered);
	printf("}\n");
	fflush(stdout);
}

static int ask(sd_bus_message *call, const char *type, const char *path, const char *passkey)
{
	struct pending *request = malloc(sizeof(*request));
	if (!request)
		return -ENOMEM;
	request->id = ++next_id;
	request->type = type;
	request->call = sd_bus_message_ref(call);
	request->next = pending;
	pending = request;
	send(request->id, type, path, passkey, -1);
	// Replied to in answer()
	return 1;
}

static void answer(char *line)
{
	char *rest;
	unsigned long id = strtoul(line, &rest, 10);
	if (rest == line || !isspace((unsigned char)*rest))
		return;
	while (isspace((unsigned char)*rest))
		rest++;
	char *word = rest;
	while (*rest && !isspace((unsigned char)*rest))
		rest++;
	if (*rest)
		*rest++ = '\0';
	while (isspace((unsigned char)*rest))
		rest++;
	char *value = rest;

	struct pending **link = &pending;
	while (*link && (*link)->id != id)
		link = &(*link)->next;
	struct pending *request = *link;
	if (!request)
		return;
	*link = request->next;

	sd_bus_message *call = request->call;
	if (strcmp(word, "yes") != 0) {
		sd_bus_reply_method_errorf(call, "org.bluez.Error.Rejected", "Rejected by the user");
	} else if (strcmp(request->type, "pin") == 0) {
		sd_bus_reply_method_return(call, "s", value);
	} else if (strcmp(request->type, "passkey") == 0) {
		char *end;
		errno = 0;
		unsigned long passkey = strtoul(value, &end, 10);
		if (end == value || *end || errno || passkey > UINT32_MAX || value[0] == '-')
			sd_bus_reply_method_errorf(call, "org.bluez.Error.Rejected", "Not a passkey");
		else
			sd_bus_reply_method_return(call, "u", (uint32_t)passkey);
	} else {
		sd_bus_reply_method_return(call, "");
	}
	sd_bus_message_unref(call);
	free(request);
}

static int release(sd_bus_message *call, void *data, sd_bus_error *error)
{
	return sd_bus_reply_method_return(call, "");
}

static int request_pin(sd_bus_message *call, void *data, sd_bus_error *error)
{
	const char *path;
	int r = sd_bus_message_read(call, "o", &path);
	return r < 0 ? r : ask(call, "pin", path, NULL);
}

static int request_passkey(sd_bus_message *call, void *data, sd_bus_error *error)
{
	const char *path;
	int r = sd_bus_message_read(call, "o", &path);
	return r < 0 ? r : ask(call, "passkey", path, NULL);
}

static int display_pin(sd_bus_message *call, void *data, sd_bus_error *error)
{
	const char *path, *pin;
	int r = sd_bus_message_read(call, "os", &path, &pin);
	if (r < 0)
		return r;
	send(0, "display-pin", path, pin, -1);
	return sd_bus_reply_method_return(call, "");
}

static int display_passkey(sd_bus_message *call, void *data, sd_bus_error *error)
{
	const char *path;
	uint32_t passkey;
	uint16_t entered;
	int r = sd_bus_message_read(call, "ouq", &path, &passkey, &entered);
	if (r < 0)
		return r;
	char code[16];
	snprintf(code, sizeof(code), "%06u", passkey);
	send(0, "display-passkey", path, code, entered);
	return sd_bus_reply_method_return(call, "");
}

static int request_confirmation(sd_bus_message *call, void *data, sd_bus_error *error)
{
	const char *path;
	uint32_t passkey;
	int r = sd_bus_message_read(call, "ou", &path, &passkey);
	if (r < 0)
		return r;
	char code[16];
	snprintf(code, sizeof(code), "%06u", passkey);
	return ask(call, "confirm", path, code);
}

static int request_authorization(sd_bus_message *call, void *data, sd_bus_error *error)
{
	const char *path;
	int r = sd_bus_message_read(call, "o", &path);
	return r < 0 ? r : ask(call, "authorize", path, NULL);
}

// Trusted devices reconnect without asking
static int authorize_service(sd_bus_message *call, void *data, sd_bus_error *error)
{
	const char *path, *uuid;
	int r = sd_bus_message_read(call, "os", &path, &uuid);
	if (r < 0)
		return r;
	if (trusted(path))
		return sd_bus_reply_method_return(call, "");
	return ask(call, "service", path, NULL);
}

static int cancel(sd_bus_message *call, void *data, sd_bus_error *error)
{
	while (pending) {
		struct pending *request = pending;
		pending = request->next;
		sd_bus_reply_method_errorf(request->call, "org.bluez.Error.Canceled", "Canceled");
		sd_bus_message_unref(request->call);
		free(request);
	}
	send(0, "cancel", NULL, NULL, -1);
	return sd_bus_reply_method_return(call, "");
}

static const sd_bus_vtable agent_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("Release", "", "", release, 0),
	SD_BUS_METHOD("RequestPinCode", "o", "s", request_pin, 0),
	SD_BUS_METHOD("RequestPasskey", "o", "u", request_passkey, 0),
	SD_BUS_METHOD("DisplayPinCode", "os", "", display_pin, 0),
	SD_BUS_METHOD("DisplayPasskey", "ouq", "", display_passkey, 0),
	SD_BUS_METHOD("RequestConfirmation", "ou", "", request_confirmation, 0),
	SD_BUS_METHOD("RequestAuthorization", "o", "", request_authorization, 0),
	SD_BUS_METHOD("AuthorizeService", "os", "", authorize_service, 0),
	SD_BUS_METHOD("Cancel", "", "", cancel, 0),
	SD_BUS_VTABLE_END,
};

static void register_agent(void)
{
	sd_bus_error error = SD_BUS_ERROR_NULL;
	if (sd_bus_call_method(bus, BUS_NAME, "/org/bluez", "org.bluez.AgentManager1", "RegisterAgent", &error, NULL, "os", AGENT_PATH, CAPABILITY) < 0 ||
	    sd_bus_call_method(bus, BUS_NAME, "/org/bluez", "org.bluez.AgentManager1", "RequestDefaultAgent", &error, NULL, "o", AGENT_PATH) < 0)
		fprintf(stderr, "bluetooth-agent: couldn't register: %s: %s\n", error.name, error.message);
	else
		fprintf(stderr, "bluetooth-agent: registered\n");
	sd_bus_error_free(&error);
}

// Re-register whenever bluetoothd restarts
static int owner_changed(sd_bus_message *signal, void *data, sd_bus_error *error)
{
	const char *name, *old, *new;
	if (sd_bus_message_read(signal, "sss", &name, &old, &new) >= 0 && strcmp(name, BUS_NAME) == 0 && *new)
		register_agent();
	return 0;
}

static int read_stdin(sd_event_source *source, int fd, uint32_t events, void *data)
{
	static char buffer[4096];
	static size_t used;

	ssize_t n = read(fd, buffer + used, sizeof(buffer) - 1 - used);
	if (n <= 0) {
		if (n < 0 && (errno == EINTR || errno == EAGAIN))
			return 0;
		return sd_event_exit(sd_event_source_get_event(source), 0);
	}
	used += n;
	buffer[used] = '\0';

	char *line = buffer, *end;
	while ((end = strchr(line, '\n'))) {
		*end = '\0';
		answer(line);
		line = end + 1;
	}
	used -= line - buffer;
	memmove(buffer, line, used);
	// Drop overlong lines
	if (used == sizeof(buffer) - 1)
		used = 0;
	return 0;
}

int main(void)
{
	sd_event *event;
	int r;

	if ((r = sd_event_default(&event)) < 0 || (r = sd_bus_open_system(&bus)) < 0) {
		fprintf(stderr, "bluetooth-agent: no system bus: %s\n", strerror(-r));
		return 1;
	}
	if ((r = sd_bus_add_object_vtable(bus, NULL, AGENT_PATH, "org.bluez.Agent1", agent_vtable, NULL)) < 0 ||
	    (r = sd_bus_match_signal(bus, NULL, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameOwnerChanged", owner_changed, NULL)) < 0 ||
	    (r = sd_bus_attach_event(bus, event, SD_EVENT_PRIORITY_NORMAL)) < 0 ||
	    (r = sd_event_add_io(event, NULL, STDIN_FILENO, EPOLLIN, read_stdin, NULL)) < 0) {
		fprintf(stderr, "bluetooth-agent: %s\n", strerror(-r));
		return 1;
	}
	register_agent();
	return sd_event_loop(event) < 0;
}
