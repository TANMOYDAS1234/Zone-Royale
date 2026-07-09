# Zone Royale multiplayer server — deployable to Render.com (free tier).
# Two-stage build: compile to a native exe, then run on a tiny runtime image.

FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

# Minimal runtime image (just the Dart runtime + our compiled server).
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server

# Render provides the PORT env var; our server reads it (defaults to 8080).
EXPOSE 8080
CMD ["/app/bin/server"]
