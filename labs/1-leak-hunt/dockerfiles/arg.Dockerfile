FROM python:3.12-slim
ARG API_KEY
RUN test -n "$API_KEY" && echo "build step got a key"
