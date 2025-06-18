FROM nginx:1.27.5-alpine-slim AS builder
ENV NGINX_VERSION=1.27.5
# Install build dependencies
RUN apk add --no-cache \    
    gcc \
    libstdc++ \
    musl-dev \
    libc-dev \
    make \
    openssl-dev \
    pcre-dev \
    pcre2-dev \
    zlib-dev \
    linux-headers \
    curl \
    gnupg \
    libxslt-dev \
    geoip-dev \
    g++ \
    git \
    libtool \
    automake \
    autoconf \
    file

# Get nginx sources for current version
WORKDIR /usr/src
RUN curl -fSL http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
    tar -zxC /usr/src -f nginx.tar.gz

FROM builder AS modsecurity

# Build ModSecurity
# Clone ModSecurity repository

WORKDIR /usr/src
RUN git clone https://github.com/owasp-modsecurity/ModSecurity.git --recurse-submodules
# RUN git submodule update --init --recursive
WORKDIR /usr/src/ModSecurity

RUN ./build.sh && \
    ./configure && \
    make && \
    make install

FROM modsecurity AS modules
WORKDIR /usr/src
RUN git clone https://github.com/SpiderLabs/ModSecurity-nginx.git

# Build ModSecurity-nginx connector
# COPY submodules/ModSecurity-nginx /usr/src/ModSecurity-nginx

WORKDIR /usr/src/nginx-${NGINX_VERSION}
RUN ./configure --with-compat --add-dynamic-module=/usr/src/ModSecurity-nginx && \
    make modules

# Final image
FROM nginx:1.27.5-alpine-slim

RUN apk add --no-cache \    
    geoip \
    libxslt \
    libstdc++

COPY --from=modsecurity /usr/local/modsecurity/ /usr/local/modsecurity/
COPY --from=modules /usr/src/nginx-*/objs/ngx_http_modsecurity_module.so /etc/nginx/modules/

# Configure ModSecurity
RUN mkdir -p /etc/nginx/modsecurity/owasp-crs /etc/nginx/modsecurity/rules
# COPY nginx/modsecurity/modsecurity.conf /etc/nginx/modsecurity/
# COPY nginx/modsecurity/owasp-crs/crs-setup.conf /etc/nginx/modsecurity/
# COPY submodules/owasp-crs/rules/ /etc/nginx/modsecurity/owasp-crs/rules/

# Add custom rules directory
COPY nginx/modsecurity/rules/ /etc/nginx/modsecurity/rules/

# Update nginx.conf to load the module
RUN echo 'load_module modules/ngx_http_modsecurity_module.so;' > /etc/nginx/modules/modsecurity.conf

# Setup logging directories
RUN mkdir -p /var/log/nginx/modsec && \
    chown -R nginx:nginx /var/log/nginx/

# Copy nginx configuration

# Copy your basic configs
# COPY nginx/nginx.conf /etc/nginx/nginx.conf
# COPY nginx/conf.d/ /etc/nginx/conf.d/

EXPOSE 80 443

# Run it to ensure it works
CMD ["nginx", "-g", "daemon off;"]