## shallow clone for speed

REBAR_GIT_CLONE_OPTIONS += --depth 1
export REBAR_GIT_CLONE_OPTIONS

REBAR = $(CURDIR)/rebar3

REBAR_URL = https://s3.amazonaws.com/rebar3/rebar3

export EMQX_DEPS_DEFAULT_VSN

PROFILE ?= emqx
PROFILES := emqx emqx-edge
PKG_PROFILES := emqx-pkg emqx-edge-pkg

CT_APPS := emqx \
        emqx_auth_clientid \
        emqx_auth_http \
        emqx_auth_jwt \
        emqx_auth_ldap \
        emqx_auth_mnesia \
        emqx_auth_mongo \
        emqx_auth_mysql \
        emqx_auth_pgsql \
        emqx_auth_redis \
        emqx_auth_username \
        emqx_bridge_mqtt \
        emqx_coap \
        emqx_dashboard \
        emqx_extension_hook \
        emqx_lua_hook \
        emqx_lwm2m \
        emqx_management \
        emqx_plugin_template \
        emqx_psk_file \
        emqx_recon \
        emqx_reloader \
        emqx_retainer \
        emqx_rule_engine \
        emqx_sasl \
        emqx_sn \
        emqx_statsd \
        emqx_stomp \
        emqx_web_hook

.PHONY: default
default: $(REBAR) $(PROFILE)

.PHONY: all
all: $(REBAR) $(PROFILES)

.PHONY: distclean
distclean:
	@rm -rf _build
	@rm -f data/app.*.config data/vm.*.args rebar.lock
	@rm -rf _checkouts

.PHONY: $(PROFILES)
$(PROFILES:%=%): $(REBAR)
ifneq ($(OS),Windows_NT)
	@ln -snf _build/$(@)/lib ./_checkouts
endif
	@if [ $$(echo $(@) |grep edge) ];then export EMQX_DESC="EMQ X Edge";else export EMQX_DESC="EMQ X Broker"; fi;\
	$(REBAR) as $(@) release

.PHONY: $(PROFILES:%=build-%)
$(PROFILES:%=build-%): $(REBAR)
	$(REBAR) as $(@:build-%=%) compile

.PHONY: deps-all
deps-all: $(REBAR) $(PROFILES:%=deps-%) $(PKG_PROFILES:%=deps-%)

.PHONY: $(PROFILES:%=deps-%)
$(PROFILES:%=deps-%): $(REBAR)
	$(REBAR) as $(@:deps-%=%) get-deps

.PHONY: $(PKG_PROFILES:%=deps-%)
$(PKG_PROFILES:%=deps-%): $(REBAR)
	$(REBAR) as $(@:deps-%=%) get-deps

.PHONY: run $(PROFILES:%=run-%)
run: run-$(PROFILE)
$(PROFILES:%=run-%): $(REBAR)
ifneq ($(OS),Windows_NT)
	@ln -snf _build/$(@:run-%=%)/lib ./_checkouts
endif
	$(REBAR) as $(@:run-%=%) run

.PHONY: clean $(PROFILES:%=clean-%)
clean: $(PROFILES:%=clean-%)
$(PROFILES:%=clean-%): $(REBAR)
	@rm -rf _build/$(@:clean-%=%)
	@rm -rf _build/$(@:clean-%=%)+test

.PHONY: $(PROFILES:%=checkout-%)
$(PROFILES:%=checkout-%): $(REBAR) build-$(PROFILE)
	ln -s -f _build/$(@:checkout-%=%)/lib ./_checkouts

# Checkout current profile
.PHONY: checkout
checkout:
	@ln -s -f _build/$(PROFILE)/lib ./_checkouts

# Run ct for an app in current profile
.PHONY: $(REBAR) $(CT_APPS:%=ct-%)
ct: $(CT_APPS:%=ct-%)
$(CT_APPS:%=ct-%): checkout-$(PROFILE)
	-make -C _build/emqx/lib/$(@:ct-%=%) ct
	@mkdir -p tests/logs/$(@:ct-%=%)
	@if [ -d _build/emqx/lib/$(@:ct-%=%)/_build/test/logs ]; then cp -r _build/emqx/lib/$(@:ct-%=%)/_build/test/logs/* tests/logs/$(@:ct-%=%); fi

$(REBAR):
ifneq ($(wildcard rebar3),rebar3)
	@curl -Lo rebar3 $(REBAR_URL) || wget $(REBAR_URL)
endif
	@chmod a+x rebar3

# Build packages
.PHONY: $(PKG_PROFILES)
$(PKG_PROFILES:%=%): $(REBAR) $(PKG_PROFILES:%=deps-%)
	ln -snf _build/$(@)/lib ./_checkouts
	@if [ $$(echo $(@) |grep edge) ];then export EMQX_DESC="EMQ X Edge";else export EMQX_DESC="EMQ X Broker"; fi;\
	$(REBAR) as $(@) release
	EMQX_REL=$$(pwd) EMQX_BUILD=$(@) make -C deploy/packages

# Build docker image
.PHONY: $(PROFILES:%=%-docker-build)
$(PROFILES:%=%-docker-build): $(PROFILES:%=deps-%)
	@if [ ! -z `echo $(@) |grep -oE edge` ]; then \
		TARGET=emqx/emqx-edge make -C deploy/docker; \
	else \
		TARGET=emqx/emqx make -C deploy/docker; \
	fi;

# Save docker images
.PHONY: $(PROFILES:%=%-docker-save)
$(PROFILES:%=%-docker-save):
	@if [ ! -z `echo $(@) |grep -oE edge` ]; then \
		TARGET=emqx/emqx-edge make -C deploy/docker save; \
	else \
		TARGET=emqx/emqx make -C deploy/docker save; \
	fi;

# Push docker image
.PHONY: $(PROFILES:%=%-docker-push)
$(PROFILES:%=%-docker-push):
	@if [ ! -z `echo $(@) |grep -oE edge` ]; then \
		TARGET=emqx/emqx-edge make -C deploy/docker push; \
		TARGET=emqx/emqx-edge make -C deploy/docker manifest_list; \
	else \
		TARGET=emqx/emqx make -C deploy/docker push; \
		TARGET=emqx/emqx make -C deploy/docker manifest_list; \
	fi;

# Clean docker image
.PHONY: $(PROFILES:%=%-docker-clean)
$(PROFILES:%=%-docker-clean):
	@if [ ! -z `echo $(@) |grep -oE edge` ]; then \
		TARGET=emqx/emqx-edge make -C deploy/docker clean; \
	else \
		TARGET=emqx/emqx make -C deploy/docker clean; \
	fi;
