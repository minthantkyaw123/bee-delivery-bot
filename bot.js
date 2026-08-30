const puppeteer = require('puppeteer');
const axios = require('axios');

async function runBankingBot() {
  console.log("Bot စတင် အလုပ်လုပ်နေပါပြီ...");
  
  let browser;
  try {
    // Chromium Browser ကို Render Server အတွက် သင့်တော်သော Option များဖြင့် ဖွင့်ခြင်း
    browser = await puppeteer.launch({
      headless: "new",
      executablePath: puppeteer.executablePath(),
      args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--single-process",
        "--no-zygote"
      ]
    });

    const page = await browser.newPage();

    // 1. ဘဏ် သို့မဟုတ် Merchant Portal Login စာမျက်နှာသို့ သွားခြင်း
    await page.goto('https://your-bank-portal.com/login', { waitUntil: 'networkidle2' });

    // 2. Login ဝင်ခြင်း (Form ထဲ စာရိုက်ထည့်ခြင်း)
    await page.type('#username-input-id', 'YOUR_USERNAME');
    await page.type('#password-input-id', 'YOUR_PASSWORD');
    await page.click('#login-button-id');

    // Login ဝင်ပြီးသွားသည်အထိ ခဏစောင့်ခြင်း
    await page.waitForNavigation({ waitUntil: 'networkidle2' });

    // 3. ငွေဝင်စာရင်း Table ထဲမှ Transaction ID နှင့် Amount များကို ဆွဲယူခြင်း
    const transactions = await page.evaluate(() => {
      let data = [];
      let rows = document.querySelectorAll('table tr'); 
      rows.forEach(row => {
        let cols = row.querySelectorAll('td');
        if (cols.length >= 2) {
          data.push({
            txnId: cols[0].innerText.trim(),
            amount: cols[1].innerText.trim()
          });
        }
      });
      return data;
    });

    console.log("တွေ့ရှိသော ငွေလွှဲစာရင်းများ -", transactions);

    // 4. Firebase Cloud Function သို့ သွားရောက် အကြောင်းကြားခြင်း
    for (let txn of transactions) {
      if (txn.txnId) {
        await axios.post('YOUR_FIREBASE_CLOUD_FUNCTION_URL', {
          transactionId: txn.txnId,
          amount: txn.amount
        });
      }
    }

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

// Server စစချင်း အရင်တစ်ကြိမ် တန်းမောင်းပေးခြင်း
runBankingBot();