# The landing page, plus the signed disk image, as static files.
# Build context is a staged copy of site/ (see deploy-site.sh).
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site/ /usr/share/nginx/html/griswold/
EXPOSE 8080
