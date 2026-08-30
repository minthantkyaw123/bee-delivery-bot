const puppeteer = require('puppeteer');
const axios = require('axios');
const express = require('express');

// Render Port Binding အတွက် Web Server သေးသေးလေး ဖွင့်ခြင်း
const app = express();
const PORT = process.env.PORT || 3000;
app.get('/', (req, res) => res.send('Bee Delivery Bot is Running!'));
app.listen(PORT, () => console.log(`Server is listening on port ${PORT}`));

async function runBankingBot() {
  console.log("Bot စတင် အလုပ်လုပ်နေပါပြီ...");
  
  let browser;
  try {
    browser = await puppeteer.launch({
      headless: "new",
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--single-process",
        "--no-zygote"
      ]
    });

    const page = await browser.newPage();
    
    // Scraper Logic
    await page.goto('https://your-bank-portal.com/login', { waitUntil: 'networkidle2' });

  } catch (error) {
    console.error("Error ဖြစ်ပွားခဲ့သည် -", error.message);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

// စက္ကန့် ၃၀ လျှင် တစ်ကြိမ် အလိုအလျောက် ပတ်ခိုင်းခြင်း
setInterval(runBankingBot, 30000);
runBankingBot();