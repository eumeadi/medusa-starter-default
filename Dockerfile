FROM node:22-alpine

WORKDIR /application


## Globally install the package manager pnpm.
#RUN npm i -g pnpm

COPY . .

RUN yarn install --frozen-lockfile

EXPOSE 9000

CMD ["sh", "docker-bootstrap.sh"]
