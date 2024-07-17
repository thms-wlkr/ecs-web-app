const express = require('express');
const app = express();

const PORT = process.env.PORT || 80;

app.get('/', (req, res) => {
  res.send('Hello! Welcome to thms-wlkr ECS hosted web-app.');
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
