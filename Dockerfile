FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY Vire.cs vire.csproj ./
RUN dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -o /out

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libicu72 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/vire /usr/local/bin/vire
WORKDIR /work
COPY checks ./checks/
COPY tests.vire term.vire vault.vire count.vire ./
ENTRYPOINT ["vire"]
