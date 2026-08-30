const puppeteer = require('puppeteer');
const axios = require('axios');

async function runBankingBot() {
  console.log("Bot စတင် အလုပ်လုပ်နေပါပြီ...");
  
  // Chromium Browser ကို နောက်ကွယ်မှ ဖွင့်ခြင်း
  const browser = await puppeteer.launch({ 
        
    const browser = await puppeteer.launch({
    headless: "new",
    args: [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--single-process",
        "--no-zygote"
    ]
    });
    
    headless: false, // စမ်းသပ်နေစဉ် ဘရောက်ဇာ ပွင့်လာတာ ကြည့်ချင်ပါက false ထားပါ
    defaultViewport: null 
  });

  const page = await browser.newPage();

  try {
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
      // Table row များကို လိုက်ဖတ်ခြင်း
      let rows = document.querySelectorAll('table tr'); 
      rows.forEach(row => {
        let cols = row.querySelectorAll('td');
        if (cols.length >= 2) {
          data.push({
            txnId: cols[0].innerText.trim(),  // Transaction ID ကော်လံ
            amount: cols[1].innerText.trim()  // ငွေပမာဏ ကော်လံ
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
    console.error("Error ဖြစ်ပွားခဲ့သည် -", error);
  } finally {
    await browser.close();
  }
}

// စက္ကန့် ၃၀ လျှင် တစ်ကြိမ် အလိုအလျောက် ပတ်ခိုင်းခြင်း
setInterval(runBankingBot, 30000);