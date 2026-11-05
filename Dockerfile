FROM mcr.microsoft.com/dotnet/sdk:8.0@sha256:6ba9644da07bb5b560a402acec9ca38711a0762969f1b61da261df5c9f6f85da AS build
WORKDIR /src
COPY Vire.cs vire.csproj ./
RUN dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -o /out

FROM debian:bookworm-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3
RUN apt-get update && apt-get install -y --no-install-recommends libicu72 libssl3 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/vire /usr/local/bin/vire
RUN useradd --create-home --uid 1000 vire \
 && chown -R vire:vire /usr/local/bin/vire
WORKDIR /work
COPY checks ./checks/
COPY systems ./systems/
COPY tests.vire term.vire vault.vire count.vire ./
RUN chown -R vire:vire /work
USER vire
ENTRYPOINT ["vire"]
