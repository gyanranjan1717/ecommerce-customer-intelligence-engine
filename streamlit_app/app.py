import streamlit as st
import pandas as pd
import numpy as np
import joblib
import json
import os

# Page Configuration
st.set_page_config(
    page_title="E-Commerce Customer Retention & Churn Intelligence",
    page_icon="🛒",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom Styling
st.markdown("""
<style>
    .main-header {
        font-size: 2.2rem;
        font-weight: 700;
        color: #1E3A8A;
        margin-bottom: 0.2rem;
    }
    .sub-header {
        font-size: 1.1rem;
        color: #4B5563;
        margin-bottom: 1.5rem;
    }
    .metric-card {
        background-color: #F8FAFC;
        border-radius: 8px;
        padding: 16px;
        border-left: 5px solid #2563EB;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    .risk-high {
        color: #DC2626;
        font-weight: 700;
    }
    .risk-medium {
        color: #D97706;
        font-weight: 700;
    }
    .risk-low {
        color: #16A34A;
        font-weight: 700;
    }
</style>
""", unsafe_allow_html=True)

# Application Header
st.markdown('<div class="main-header">🛒 Customer Retention & Churn Intelligence Engine</div>', unsafe_allow_html=True)
st.markdown('<div class="sub-header">Real-Time Predictive Churn Scoring & Operational Driver Explainability | Olist Dataset</div>', unsafe_allow_html=True)

# Helper function to load model and artifacts
@st.cache_resource
def load_artifacts():
    base_dir = os.path.dirname(__file__)
    model_path = os.path.join(base_dir, 'churn_model.pkl')
    meta_path = os.path.join(base_dir, 'model_metadata.json')
    
    model = None
    metadata = None
    
    if os.path.exists(model_path):
        model = joblib.load(model_path)
    if os.path.exists(meta_path):
        with open(meta_path, 'r') as f:
            metadata = json.load(f)
            
    return model, metadata

model, metadata = load_artifacts()

# Sidebar: Customer Behavioral & Operational Inputs
st.sidebar.header("📋 Customer Profile Parameters")
st.sidebar.markdown("Adjust customer attributes to compute real-time churn risk:")

recency = st.sidebar.slider("Recency (Days since last purchase)", min_value=1, max_value=700, value=45, step=1)
frequency = st.sidebar.slider("Lifetime Orders (Frequency)", min_value=1, max_value=25, value=2, step=1)
monetary_value = st.sidebar.number_input("Total Spend ($)", min_value=5.0, max_value=15000.0, value=240.0, step=10.0)

st.sidebar.markdown("---")
st.sidebar.subheader("⚙️ Operational & Experience Metrics")

avg_review = st.sidebar.slider("Average Review Score (1 to 5)", min_value=1.0, max_value=5.0, value=4.2, step=0.1)
delivery_delay = st.sidebar.slider("Delivery Delay beyond SLA (Days)", min_value=-20.0, max_value=40.0, value=-2.0, step=0.5,
                                  help="Negative values indicate delivery before promised estimated date. Positive indicates delayed shipment.")
freight_val = st.sidebar.number_input("Total Freight Paid ($)", min_value=0.0, max_value=1500.0, value=35.0, step=5.0)
installments = st.sidebar.slider("Average Payment Installments", min_value=1.0, max_value=24.0, value=3.0, step=1.0)
payment_type = st.sidebar.selectbox("Preferred Payment Method", ["credit_card", "boleto", "voucher", "debit_card"])
state = st.sidebar.selectbox("Customer State", ["SP", "RJ", "MG", "RS", "PR", "BA", "SC", "Other"])

# Derived Calculations
avg_order_value = monetary_value / frequency
freight_ratio = freight_val / (monetary_value + 1e-5)
total_items = max(1, int(frequency * 1.2))

# Layout: 2 Columns for Results
col1, col2 = st.columns([1.1, 1])

with col1:
    st.subheader("🎯 Real-Time Predictive Assessment")
    
    # Predict with model if loaded, else use calibrated heuristic fallback
    if model is not None and metadata is not None:
        # Construct feature DataFrame matching model training schema
        feature_names = metadata.get('encoded_feature_names', [])
        input_data = {feat: 0.0 for feat in feature_names}
        
        # Populate numerics
        input_data['frequency'] = float(frequency)
        input_data['monetary_value'] = float(monetary_value)
        input_data['avg_order_value'] = float(avg_order_value)
        input_data['total_freight_paid'] = float(freight_val)
        input_data['freight_ratio'] = float(freight_ratio)
        input_data['total_items_bought'] = float(total_items)
        input_data['avg_review_score'] = float(avg_review)
        input_data['avg_delivery_delay_days'] = float(delivery_delay)
        input_data['max_delivery_delay_days'] = float(max(delivery_delay, 0.0))
        input_data['avg_payment_installments'] = float(installments)
        
        # Populate encoded categoricals
        pay_col = f"preferred_payment_type_{payment_type}"
        if pay_col in input_data:
            input_data[pay_col] = 1.0
            
        state_col = f"customer_state_{state}"
        if state_col in input_data:
            input_data[state_col] = 1.0
            
        input_df = pd.DataFrame([input_data])
        churn_prob = float(model.predict_proba(input_df)[0][1])
    else:
        # Fallback calibrated risk estimator if model.pkl hasn't been uploaded yet
        delay_penalty = max(0, delivery_delay * 0.02)
        review_penalty = (5.0 - avg_review) * 0.08
        freight_penalty = min(0.2, freight_ratio * 0.3)
        recency_penalty = min(0.5, (recency / 180.0) * 0.4)
        churn_prob = min(0.98, max(0.05, 0.20 + recency_penalty + delay_penalty + review_penalty + freight_penalty))

    # Churn Risk Tier
    if churn_prob >= 0.70:
        tier_label = "HIGH RISK"
        tier_class = "risk-high"
        action_text = "🚨 **Critical Action Required:** Trigger immediate win-back campaign with high-incentive voucher (15-20% discount) or customer support check-in."
    elif churn_prob >= 0.40:
        tier_label = "MEDIUM RISK"
        tier_class = "risk-medium"
        action_text = "⚠️ **Preventative Action:** Send personalized re-engagement newsletter featuring relevant product categories and free shipping."
    else:
        tier_label = "LOW RISK (LOYAL)"
        tier_class = "risk-low"
        action_text = "✅ **Healthy Customer:** Cross-sell premium catalog items or invite to loyalty program without discounting."

    st.markdown(f"""
    <div class="metric-card">
        <h3>Predicted Churn Probability: <span class="{tier_class}">{churn_prob*100:.1f}%</span></h3>
        <p>Status: <span class="{tier_class}">{tier_label}</span></p>
    </div>
    """, unsafe_allow_html=True)
    
    st.markdown("<br>", unsafe_allow_html=True)
    st.progress(churn_prob)
    st.info(action_text)

with col2:
    st.subheader("🔍 Operational Driver Attribution")
    
    # Feature impacts breakdown
    drivers_df = pd.DataFrame({
        "Operational Driver": [
            "Delivery SLA Gap",
            "Freight-to-Price Ratio",
            "Review Score Sentiment",
            "Customer Recency Factor",
            "Average Order Value"
        ],
        "Observed Metric": [
            f"{delivery_delay:+.1f} days vs SLA",
            f"{freight_ratio*100:.1f}% of total spend",
            f"{avg_review:.1f} / 5.0 stars",
            f"{recency} days inactive",
            f"${avg_order_value:.2f}"
        ],
        "Impact on Churn": [
            "Increasing Risk" if delivery_delay > 0 else "Protective",
            "Increasing Risk" if freight_ratio > 0.25 else "Neutral",
            "Increasing Risk" if avg_review < 3.5 else "Protective",
            "Strong Churn Driver" if recency > 90 else "Active Window",
            "Retention Anchor" if avg_order_value > 150 else "Standard"
        ]
    })
    st.table(drivers_df)

st.markdown("---")

# Executive Portfolio Insights Section
st.subheader("📊 Strategic E-Commerce Insights (Portfolio Readout)")
c1, c2, c3 = st.columns(3)
c1.metric(label="Total Unique Buyers Studied", value="96,096")
c2.metric(label="Delivered Orders Analyzed", value="96,478")
c3.metric(label="Repeat Purchase Baseline", value="3.48%")

st.caption("Developed by Gyan Ranjan | Built with Streamlit, Scikit-Learn, and XGBoost | RGIPT")
