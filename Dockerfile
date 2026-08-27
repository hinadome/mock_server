FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
COPY src/dashboard/templates ./dist/dashboard/templates
COPY docs ./docs
EXPOSE 3000 3001 50051 1883
ENV HOST=0.0.0.0
CMD ["npm", "start"]
