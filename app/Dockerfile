FROM nginx:alpine

COPY index.html /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /usr/share/nginx/html/data && \
    echo "Persistent data volume" > /usr/share/nginx/html/data/hello.txt
