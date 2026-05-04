FROM node:22-bookworm

WORKDIR /app

COPY package.json tsconfig.json ./
RUN npm install

COPY src ./src
COPY data ./data

RUN npm run build

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000
ENV DB_PATH=/app/data/vipgames.db

EXPOSE 3000

CMD ["npm", "run", "start"]
