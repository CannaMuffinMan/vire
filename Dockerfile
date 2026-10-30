# Digests from MCR manifest lists for the 10.0 tags (linux/amd64 included).
FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:de4fe90a98845d75910b9769662465c84de1a934665c431279d1382b2bddc02b AS build
WORKDIR /src
COPY Vire.cs Compiled.cs VirePaths.cs VireSeal.cs VireNet.cs VireFiles.cs vire.csproj ./
RUN dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -p:DebugType=none -o /out

FROM mcr.microsoft.com/dotnet/runtime-deps:10.0@sha256:62028293921f5bd6db3d9f9119cd29cd926dfd3c2336da23b09f425e40c3c832
COPY --from=build /out/vire /usr/local/bin/vire
RUN useradd --create-home vire \
 && chown vire:vire /usr/local/bin/vire
WORKDIR /work
COPY checks ./checks/
COPY systems ./systems/
COPY tests.vire term.vire vault.vire count.vire ./
RUN chown -R vire:vire /work
USER vire
ENTRYPOINT ["vire"]
