-- ============================================================================
-- RISING SON - PRINT ON DEMAND (BARIPADA, ODISHA)
-- Supabase PostgreSQL Schema, RLS Security Policies & Storage Setup
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone TEXT,
    role TEXT NOT NULL DEFAULT 'customer',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT chk_profiles_role CHECK (role IN ('customer', 'admin', 'staff', 'delivery_partner')),
    CONSTRAINT chk_profiles_full_name_not_empty CHECK (length(trim(full_name)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON public.profiles(phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_created_at ON public.profiles(created_at DESC);

-- 2. Customer Delivery Addresses
CREATE TABLE IF NOT EXISTS public.addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    recipient_name TEXT NOT NULL,
    phone TEXT NOT NULL,
    address_line_1 TEXT NOT NULL,
    address_line_2 TEXT,
    locality TEXT NOT NULL,
    landmark TEXT,
    city TEXT NOT NULL DEFAULT 'Baripada',
    state TEXT NOT NULL DEFAULT 'Odisha',
    postal_code TEXT NOT NULL,
    delivery_instructions TEXT,
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_addresses_user_id ON public.addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_addresses_postal_code ON public.addresses(postal_code);

-- 3. Collections
CREATE TABLE IF NOT EXISTS public.collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    description TEXT,
    image_path TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_collections_slug ON public.collections(slug);
CREATE INDEX IF NOT EXISTS idx_collections_is_active ON public.collections(is_active);

-- 4. Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    description TEXT,
    collection_id UUID REFERENCES public.collections(id) ON DELETE SET NULL,
    base_price NUMERIC(10, 2) NOT NULL,
    is_featured BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT chk_products_name_not_empty CHECK (length(trim(name)) > 0),
    CONSTRAINT chk_products_base_price_non_negative CHECK (base_price >= 0)
);

CREATE INDEX IF NOT EXISTS idx_products_slug ON public.products(slug);
CREATE INDEX IF NOT EXISTS idx_products_collection_id ON public.products(collection_id);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON public.products(is_active);
CREATE INDEX IF NOT EXISTS idx_products_featured ON public.products(is_featured) WHERE is_featured = true;
CREATE INDEX IF NOT EXISTS idx_products_created_at_desc ON public.products(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_products_search_gin ON public.products USING GIN (to_tsvector('english', name || ' ' || COALESCE(description, '')));

-- 5. Designs (Store Owner Managed)
CREATE TABLE IF NOT EXISTS public.designs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    design_name TEXT NOT NULL,
    artwork_path TEXT NOT NULL,
    front_mockup_path TEXT,
    back_mockup_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT chk_designs_name_not_empty CHECK (length(trim(design_name)) > 0),
    CONSTRAINT chk_designs_artwork_path_not_empty CHECK (length(trim(artwork_path)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_designs_product_id ON public.designs(product_id);
CREATE INDEX IF NOT EXISTS idx_designs_name ON public.designs(design_name);

-- 6. Product Variants (Color, Size, SKU combinations)
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    design_id UUID NOT NULL REFERENCES public.designs(id) ON DELETE CASCADE,
    color_name TEXT NOT NULL,
    color_code TEXT NOT NULL,
    size TEXT NOT NULL,
    sku TEXT NOT NULL UNIQUE,
    price NUMERIC(10, 2) NOT NULL,
    is_available BOOLEAN NOT NULL DEFAULT true,
    inventory_quantity INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT uq_product_variant_combination UNIQUE (product_id, design_id, color_name, size),
    CONSTRAINT chk_variant_size CHECK (size IN ('S', 'M', 'L', 'XL', 'XXL')),
    CONSTRAINT chk_variant_price_non_negative CHECK (price >= 0),
    CONSTRAINT chk_variant_inventory_non_negative CHECK (inventory_quantity >= 0),
    CONSTRAINT chk_variant_color_code_hex CHECK (color_code ~* '^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$'),
    CONSTRAINT chk_variant_color_name_not_empty CHECK (length(trim(color_name)) > 0),
    CONSTRAINT chk_variant_sku_not_empty CHECK (length(trim(sku)) >= 3)
);

CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_design_id ON public.product_variants(design_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_lookup ON public.product_variants(product_id, color_name, size);
CREATE INDEX IF NOT EXISTS idx_product_variants_in_stock ON public.product_variants(product_id, is_available, inventory_quantity) WHERE is_available = true AND inventory_quantity > 0;

-- 7. Shopping Cart Items
CREATE TABLE IF NOT EXISTS public.cart_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity INT NOT NULL CHECK (quantity > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_cart_user_variant UNIQUE (user_id, variant_id)
);

CREATE INDEX IF NOT EXISTS idx_cart_items_user_id ON public.cart_items(user_id);

-- 8. Orders Table (With immutable snapshots)
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number TEXT NOT NULL UNIQUE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    delivery_address_snapshot JSONB NOT NULL,
    subtotal NUMERIC(10, 2) NOT NULL,
    delivery_fee NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    discount_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    tax_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    total_amount NUMERIC(10, 2) NOT NULL,
    payment_status TEXT NOT NULL DEFAULT 'AWAITING_PAYMENT',
    production_status TEXT NOT NULL DEFAULT 'QUEUED',
    delivery_status TEXT NOT NULL DEFAULT 'PENDING',
    overall_status TEXT NOT NULL DEFAULT 'AWAITING_PAYMENT',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT chk_orders_payment_status CHECK (payment_status IN ('AWAITING_PAYMENT', 'PAID', 'FAILED', 'REFUNDED')),
    CONSTRAINT chk_orders_production_status CHECK (production_status IN ('QUEUED', 'CONFIRMED', 'PRINTING_IN_PROGRESS', 'QUALITY_CHECK', 'PACKED', 'CANCELLED')),
    CONSTRAINT chk_orders_delivery_status CHECK (delivery_status IN ('PENDING', 'ASSIGNED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'FAILED_ATTEMPT')),
    CONSTRAINT chk_orders_subtotal_non_negative CHECK (subtotal >= 0),
    CONSTRAINT chk_orders_delivery_fee_non_negative CHECK (delivery_fee >= 0),
    CONSTRAINT chk_orders_discount_non_negative CHECK (discount_amount >= 0),
    CONSTRAINT chk_orders_tax_non_negative CHECK (tax_amount >= 0),
    CONSTRAINT chk_orders_total_non_negative CHECK (total_amount >= 0),
    CONSTRAINT chk_orders_total_calculation CHECK (total_amount = ROUND(subtotal + delivery_fee + tax_amount - discount_amount, 2))
);

CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at_desc ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders(payment_status);
CREATE INDEX IF NOT EXISTS idx_orders_production_status ON public.orders(production_status);
CREATE INDEX IF NOT EXISTS idx_orders_delivery_status ON public.orders(delivery_status);
CREATE INDEX IF NOT EXISTS idx_orders_production_queue ON public.orders(payment_status, production_status, created_at ASC) WHERE payment_status = 'PAID';
CREATE INDEX IF NOT EXISTS idx_orders_delivery_address_gin ON public.orders USING GIN (delivery_address_snapshot);

-- 9. Order Items Table
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name_snapshot TEXT NOT NULL,
    design_name_snapshot TEXT NOT NULL,
    color_snapshot TEXT NOT NULL,
    size_snapshot TEXT NOT NULL,
    sku_snapshot TEXT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    line_total NUMERIC(10, 2) NOT NULL CHECK (line_total = ROUND(unit_price * quantity, 2)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_variant_id ON public.order_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_order_items_sku ON public.order_items(sku_snapshot);

-- 10. Payments (Prepaid online records)
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    gateway TEXT NOT NULL DEFAULT 'RAZORPAY',
    gateway_order_id TEXT NOT NULL,
    gateway_payment_id TEXT UNIQUE,
    amount NUMERIC(10, 2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'INR',
    status TEXT NOT NULL CHECK (status IN ('CREATED', 'AUTHORIZED', 'CAPTURED', 'FAILED', 'REFUNDED')),
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 11. Order Status Audit History
CREATE TABLE IF NOT EXISTS public.order_status_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    previous_status TEXT,
    new_status TEXT NOT NULL,
    changed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 12. Delivery Assignments (Local Baripada Fulfillment)
CREATE TABLE IF NOT EXISTS public.delivery_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    delivery_person_name TEXT NOT NULL,
    delivery_person_phone TEXT NOT NULL,
    delivery_partner TEXT NOT NULL DEFAULT 'Rising Son In-House Express',
    status TEXT NOT NULL DEFAULT 'ASSIGNED' CHECK (status IN ('ASSIGNED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'FAILED')),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    delivered_at TIMESTAMPTZ,
    failure_reason TEXT
);

-- 13. Serviceable Areas (Baripada, Odisha)
CREATE TABLE IF NOT EXISTS public.serviceable_areas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    city TEXT NOT NULL DEFAULT 'Baripada',
    locality TEXT NOT NULL,
    postal_code TEXT NOT NULL,
    delivery_fee NUMERIC(10, 2) NOT NULL DEFAULT 40.00,
    is_active BOOLEAN NOT NULL DEFAULT true,
    CONSTRAINT uq_serviceable_area UNIQUE (city, postal_code, locality)
);

-- 14. Store Settings
CREATE TABLE IF NOT EXISTS public.store_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    setting_key TEXT NOT NULL UNIQUE,
    setting_value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.designs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.serviceable_areas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_settings ENABLE ROW LEVEL SECURITY;

-- Security Helper Functions
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('admin', 'staff')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.is_delivery_partner()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'delivery_partner'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Prevent users from escalating their own role
CREATE OR REPLACE FUNCTION public.prevent_role_escalation()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role <> OLD.role AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Unauthorized: Only administrators can modify user roles';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trigger_prevent_role_escalation ON public.profiles;
CREATE TRIGGER trigger_prevent_role_escalation
    BEFORE UPDATE OF role ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_role_escalation();

-- Profiles: Users see/edit own profile, Admins see all
CREATE POLICY "profiles_select_own_or_admin" ON public.profiles FOR SELECT USING (auth.uid() = id OR public.is_admin());
CREATE POLICY "profiles_update_own" ON public.profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_admin_all" ON public.profiles FOR ALL USING (public.is_admin());

-- Addresses: Users manage own addresses, Admins can view
CREATE POLICY "addresses_select_own_or_admin" ON public.addresses FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "addresses_insert_own" ON public.addresses FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "addresses_update_own" ON public.addresses FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "addresses_delete_own" ON public.addresses FOR DELETE USING (auth.uid() = user_id);

-- Catalog Tables: Publicly readable active items, write access restricted to Admins
CREATE POLICY "collections_read_active" ON public.collections FOR SELECT USING (is_active = true OR public.is_admin());
CREATE POLICY "collections_admin_manage" ON public.collections FOR ALL USING (public.is_admin());

CREATE POLICY "products_read_active" ON public.products FOR SELECT USING (is_active = true OR public.is_admin());
CREATE POLICY "products_admin_manage" ON public.products FOR ALL USING (public.is_admin());

CREATE POLICY "designs_read_public" ON public.designs FOR SELECT USING (true);
CREATE POLICY "designs_admin_manage" ON public.designs FOR ALL USING (public.is_admin());

CREATE POLICY "variants_read_public" ON public.product_variants FOR SELECT USING (is_available = true OR public.is_admin());
CREATE POLICY "variants_admin_manage" ON public.product_variants FOR ALL USING (public.is_admin());

-- Cart: Users manage their own cart only
CREATE POLICY "cart_select_own" ON public.cart_items FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "cart_insert_own" ON public.cart_items FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "cart_update_own" ON public.cart_items FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "cart_delete_own" ON public.cart_items FOR DELETE USING (auth.uid() = user_id);

-- Orders: Customers read own orders, create initial checkout orders; Admins manage fulfillment
CREATE POLICY "orders_select_own_or_admin" ON public.orders FOR SELECT USING (auth.uid() = user_id OR public.is_admin() OR public.is_delivery_partner());
CREATE POLICY "orders_insert_customer" ON public.orders FOR INSERT WITH CHECK (auth.uid() = user_id AND payment_status = 'AWAITING_PAYMENT');
CREATE POLICY "orders_admin_manage" ON public.orders FOR ALL USING (public.is_admin());

-- Order Items
CREATE POLICY "order_items_select_own_or_admin" ON public.order_items FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND (orders.user_id = auth.uid() OR public.is_admin() OR public.is_delivery_partner()))
);
CREATE POLICY "order_items_insert_customer" ON public.order_items FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.user_id = auth.uid())
);
CREATE POLICY "order_items_admin_manage" ON public.order_items FOR ALL USING (public.is_admin());

-- Payments: Viewable by order owner & admin; write restricted to backend/admin
CREATE POLICY "payments_select_own_or_admin" ON public.payments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = payments.order_id AND (orders.user_id = auth.uid() OR public.is_admin()))
);
CREATE POLICY "payments_admin_manage" ON public.payments FOR ALL USING (public.is_admin());

-- Status History & Delivery Assignments
CREATE POLICY "history_select_own_or_admin" ON public.order_status_history FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_status_history.order_id AND (orders.user_id = auth.uid() OR public.is_admin()))
);
CREATE POLICY "history_admin_write" ON public.order_status_history FOR INSERT WITH CHECK (public.is_admin() OR public.is_delivery_partner());

CREATE POLICY "delivery_select_own_or_staff" ON public.delivery_assignments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = delivery_assignments.order_id AND (orders.user_id = auth.uid() OR public.is_admin() OR public.is_delivery_partner()))
);
CREATE POLICY "delivery_admin_manage" ON public.delivery_assignments FOR ALL USING (public.is_admin() OR public.is_delivery_partner());

-- Serviceable areas: Public read, Admin write
CREATE POLICY "areas_read_public" ON public.serviceable_areas FOR SELECT USING (true);
CREATE POLICY "areas_admin_manage" ON public.serviceable_areas FOR ALL USING (public.is_admin());

-- Store settings: Public read, Admin write
CREATE POLICY "settings_read_public" ON public.store_settings FOR SELECT USING (true);
CREATE POLICY "settings_admin_manage" ON public.store_settings FOR ALL USING (public.is_admin());

-- ============================================================================
-- SEED DATA FOR BARIPADA, ODISHA
-- ============================================================================

INSERT INTO public.serviceable_areas (city, locality, postal_code, delivery_fee, is_active) VALUES
('Baripada', 'Lal Bazar / Main Road', '757001', 40.00, true),
('Baripada', 'Deulasahi / Temple Area', '757001', 40.00, true),
('Baripada', 'Station Road / Ward 1-5', '757001', 40.00, true),
('Baripada', 'Bhanjpur / Baghra Road', '757002', 40.00, true),
('Baripada', 'Takatpur / MPC Campus', '757003', 40.00, true),
('Baripada', 'Baripada R.S. / Madhuban', '757004', 40.00, true)
ON CONFLICT DO NOTHING;

INSERT INTO public.store_settings (setting_key, setting_value) VALUES
('general_branding', '{"brand_name": "Rising Son", "tagline": "Baripada Local Streetwear", "city": "Baripada", "state": "Odisha"}'::jsonb),
('contact_details', '{"phone": "+91 94370 12345", "whatsapp": "+91 94370 12345", "email": "care@risingson.in"}'::jsonb),
('fulfillment_rules', '{"default_delivery_fee": 40.00, "free_delivery_threshold": 999.00, "estimated_hours": 24}'::jsonb)
ON CONFLICT DO NOTHING;
