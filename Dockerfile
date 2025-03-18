FROM nginx:alpine AS builder

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

FROM builder AS modsecurity

# Build ModSecurity
COPY submodules/modsecurity /usr/src/modsecurity
WORKDIR /usr/src/modsecurity
RUN ./build.sh && \
    ./configure && \
    make && \
    make install

# Get nginx sources for current version
WORKDIR /usr/src
RUN nginx_version=$(nginx -v 2>&1 | sed 's/^nginx version: nginx\///') && \
    curl -fSL http://nginx.org/download/nginx-${nginx_version}.tar.gz -o nginx.tar.gz && \
    tar -zxC /usr/src -f nginx.tar.gz

# Build ModSecurity-nginx connector
COPY submodules/modsecurity-nginx /usr/src/modsecurity-nginx
RUN nginx_version=$(nginx -v 2>&1 | sed 's/^nginx version: nginx\///') && \
    cd /usr/src/nginx-${nginx_version} && \
    ./configure --with-compat --add-dynamic-module=/usr/src/modsecurity-nginx && \
    make modules

# Final image
FROM builder
COPY --from=modsecurity /usr/src/nginx-*/objs/ngx_http_modsecurity_module.so /etc/nginx/modules/
COPY --from=modsecurity /usr/local/modsecurity/ /usr/local/modsecurity/

# Configure ModSecurity
RUN mkdir -p /etc/nginx/modsecurity/owasp-crs /etc/nginx/modsecurity/rules
COPY nginx/modsecurity/modsecurity.conf /etc/nginx/modsecurity/
COPY nginx/modsecurity/owasp-crs/crs-setup.conf /etc/nginx/modsecurity/
COPY submodules/owasp-crs/rules/ /etc/nginx/modsecurity/owasp-crs/rules/

# Add custom rules directory
COPY nginx/modsecurity/rules/ /etc/nginx/modsecurity/rules/

# Update nginx.conf to load the module
RUN echo 'load_module modules/ngx_http_modsecurity_module.so;' > /etc/nginx/modules/modsecurity.conf

# Setup logging directories
RUN mkdir -p /var/log/nginx/modsec && \
    chown -R nginx:nginx /var/log/nginx/

# Copy nginx configuration
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d/ /etc/nginx/conf.d/

EXPOSE 80 443

# Run it to ensure it works
CMD ["nginx", "-g", "daemon off;"]