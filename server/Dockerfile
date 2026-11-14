FROM python:3.12-alpine
WORKDIR /app
COPY backup_server.py .
VOLUME /data
EXPOSE 8085
ENV PORT=8085
CMD ["python", "-u", "backup_server.py"]
