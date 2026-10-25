FROM python:3.12-slim
RUN --mount=type=secret,id=api_key test -s /run/secrets/api_key && echo "build step got a key"
