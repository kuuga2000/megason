vcl 4.1;

backend default {
    .host = "nginx";
    .port = "80";
    .first_byte_timeout = 600s;
}
