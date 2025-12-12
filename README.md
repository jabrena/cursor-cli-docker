# cursor-cli-docker

Docker image with Cursor CLI installed and ready to use.

## Building the Image

```bash
docker build -t cursor-cli .

docker run -it -e CURSOR_API_KEY=your_api_key_here cursor-cli

docker run -it -e CURSOR_API_KEY=your_api_key_here cursor-cli cursor-agent <command>

docker run -it -e CURSOR_API_KEY=your_api_key_here cursor-cli cursor-agent --help
```

## Notes

- The `CURSOR_API_KEY` environment variable must be provided at runtime for authentication
- The API key is not hardcoded in the Dockerfile for security reasons
- The cursor-cli is installed to `/root/.local/bin` and added to the PATH

## References

- https://cursor.com/docs/cli/headless
- https://cursor.com/docs/cli/github-actions
- https://cursor.com/docs/cli/reference/permissions