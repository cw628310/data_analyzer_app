import cors from 'cors';
import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const dataDir = path.join(__dirname, 'data');
const rulesFile = path.join(dataDir, 'learning-rules.json');

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '1mb' }));

app.get('/health', (_, response) => {
  response.json({ ok: true });
});

app.post('/learn/side-summary', async (request, response) => {
  const result = await learnAndOptimize({
    type: 'side',
    summary: request.body?.summary,
    context: {
      sideName: request.body?.sideName,
      reference: request.body?.reference,
    },
  });
  response.json(result);
});

app.post('/learn/combined-summary', async (request, response) => {
  const result = await learnAndOptimize({
    type: 'combined',
    summary: request.body?.summary,
    context: {
      reference: request.body?.reference,
      leftReference: request.body?.leftReference,
      rightReference: request.body?.rightReference,
    },
  });
  response.json(result);
});

async function learnAndOptimize({ type, summary, context }) {
  const safeSummary = typeof summary === 'string' ? summary.trim() : '';
  if (!safeSummary) {
    return { optimizedSummary: '', learned: false };
  }

  const rules = await readRules();
  const extracted = extractIdeas(safeSummary);
  mergeRules(rules, extracted);
  rules.history.unshift({
    type,
    context,
    summary: safeSummary,
    learnedAt: new Date().toISOString(),
  });
  rules.history = rules.history.slice(0, 200);
  await writeRules(rules);

  return {
    optimizedSummary: optimizeSummary(safeSummary, rules),
    learned: true,
    learnedIdeas: extracted,
  };
}

function extractIdeas(summary) {
  const ideas = {
    coreNumberRules: [],
    supportNumberRules: [],
    weakNumberRules: [],
    blueBallRules: [],
    combinationRules: [],
    warningRules: [],
  };

  const sentences = summary
    .split(/[。；;\n]/)
    .map((item) => item.trim())
    .filter(Boolean);

  for (const sentence of sentences) {
    if (hasAny(sentence, ['核心', '强支撑', '热号', '高频', '共现'])) {
      ideas.coreNumberRules.push(sentence);
    }
    if (hasAny(sentence, ['搭配', '中间支撑', '中频', '连接号', '组合依据'])) {
      ideas.supportNumberRules.push(sentence);
    }
    if (hasAny(sentence, ['较弱', '弱补', '补充', '冷补', '偏低'])) {
      ideas.weakNumberRules.push(sentence);
    }
    if (hasAny(sentence, ['蓝球', '冷蓝', '热蓝', '中频蓝'])) {
      ideas.blueBallRules.push(sentence);
    }
    if (hasAny(sentence, ['原始组合', '最接近', '重组', '交叉', '综合'])) {
      ideas.combinationRules.push(sentence);
    }
    if (hasAny(sentence, ['不代表中奖预测', '统计相似性', '购买情况数据'])) {
      ideas.warningRules.push(sentence);
    }
  }

  return ideas;
}

function optimizeSummary(summary, rules) {
  const additions = [];
  const topCore = topRule(rules.coreNumberRules);
  const topSupport = topRule(rules.supportNumberRules);
  const topWeak = topRule(rules.weakNumberRules);
  const topCombination = topRule(rules.combinationRules);
  const topWarning = topRule(rules.warningRules);

  if (topCore) {
    additions.push(`学习库补充：核心号码优先参考“${topCore}”。`);
  }
  if (topSupport) {
    additions.push(`学习库补充：搭配号码优先参考“${topSupport}”。`);
  }
  if (topWeak) {
    additions.push(`学习库补充：弱补号码优先参考“${topWeak}”。`);
  }
  if (topCombination) {
    additions.push(`学习库补充：组合来源优先参考“${topCombination}”。`);
  }
  if (topWarning && !summary.includes('不代表中奖预测')) {
    additions.push('最终提示：该结果只代表购买情况数据中的统计相似性和组合思路，不代表中奖预测。');
  }

  if (additions.length === 0) {
    return summary;
  }
  return `${summary}\n\n${dedupe(additions).join('\n\n')}`;
}

function mergeRules(rules, extracted) {
  for (const key of Object.keys(extracted)) {
    for (const text of extracted[key]) {
      const normalized = normalize(text);
      if (!normalized) {
        continue;
      }
      const existing = rules[key].find((item) => item.normalized === normalized);
      if (existing) {
        existing.count += 1;
        existing.updatedAt = new Date().toISOString();
      } else {
        rules[key].push({
          text,
          normalized,
          count: 1,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        });
      }
    }
    rules[key].sort((a, b) => b.count - a.count);
    rules[key] = rules[key].slice(0, 80);
  }
}

async function readRules() {
  try {
    const content = await fs.readFile(rulesFile, 'utf8');
    return JSON.parse(content);
  } catch {
    return {
      coreNumberRules: [],
      supportNumberRules: [],
      weakNumberRules: [],
      blueBallRules: [],
      combinationRules: [],
      warningRules: [],
      history: [],
    };
  }
}

async function writeRules(rules) {
  await fs.mkdir(dataDir, { recursive: true });
  await fs.writeFile(rulesFile, JSON.stringify(rules, null, 2), 'utf8');
}

function hasAny(text, keywords) {
  return keywords.some((keyword) => text.includes(keyword));
}

function normalize(text) {
  return text.replace(/\s+/g, '').replace(/[，。；;：:]/g, '').trim();
}

function topRule(items) {
  if (!Array.isArray(items) || items.length === 0) {
    return '';
  }
  return items[0].text;
}

function dedupe(items) {
  return [...new Set(items)];
}

app.listen(port, () => {
  console.log(`learning backend listening on ${port}`);
});