# Varnish Cache Command Compilation Service

A HTTP service that compiles C source code into shared objects (.so
files) for use with Varnish Cache. This service provides remote
compilation service.

This service accepts C source files via HTTP POST requests, compiles them using
GCC with specific security flags, and returns the compiled shared objects. It's
designed to work in conjunction with the Varnish Cache command compiler client.

## Configuration

### Environment Variables

- `VS_GCC_PORT`: Port number for the service (default: "8080")

## API Endpoints

### POST /compile

Compiles a C source file into a shared object.

#### Request
- Method: POST
- Content-Type: multipart/form-data
- Form Field: `source` (C source file)
- Max File Size: 10MB

#### Response
```json
{
    "success": true|false,
    "error": "error message if compilation failed",
    "binary": "base64 encoded compiled binary"
}
```

## Compilation Settings

The service uses the following GCC flags for compilation:

```bash
gcc -g -O2 -ffile-prefix-map=[tmpdir]=. -fstack-protector-strong \
    -Wformat -Werror=format-security -Wall -Werror \
    -Wno-error=unused-result -pthread -fpic -shared -Wl,-x
```

### Systemd Service Example

```ini
[Unit]
Description=Varnish Cache Command Compilation Service
After=network.target

[Service]
ExecStart=/usr/local/bin/vcc-service
Environment=VS_GCC_PORT=8080
User=vcc-service
Group=vcc-service
WorkingDirectory=/var/lib/vcc-service
Restart=always

[Install]
WantedBy=multi-user.target
```
