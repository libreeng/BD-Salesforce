FROM nginx:stable-alpine
WORKDIR /etc/nginx/conf.d

#SHELL ["/bin/bash", "-c"]
RUN echo $'server {\n\
    listen 80;\n\
    server_name localhost;\n\
\n\
    location / {\n\
        if ($request_method = "OPTIONS") {\n\
            add_header Access-Control-Allow-Origin $http_origin;\n\
            add_header Access-Control-Allow-Methods "GET, OPTIONS";\n\
            add_header "Access-Control-Allow-Headers" "DNT,User-Agent,X-Api-Key,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range";\n\
            add_header Content-Type text/plain;\n\
            add_header Content-Length 0;\n\
            return 204;\n\
        }\n\
        proxy_pass https://api.librestream.com;\n\
        proxy_hide_header X-XSS-Protection;\n\
        proxy_hide_header Access-Control-Allow-Origin;\n\
        add_header Access-Control-Allow-Origin $http_origin;\n\
    }\n\
}' > default.conf
