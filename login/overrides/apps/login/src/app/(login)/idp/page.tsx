import { DynamicTheme } from "@/components/dynamic-theme";
import { SignInWithIdp } from "@/components/sign-in-with-idp";
import { Translated } from "@/components/translated";
import { getServiceConfig } from "@/lib/service-url";
// LCMC: getDefaultOrg, Organization (Deployment/login override, see below)
import { getActiveIdentityProviders, getBrandingSettings, getDefaultOrg } from "@/lib/zitadel";
import { Organization } from "@zitadel/proto/zitadel/org/v2/org_pb";
import { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { headers } from "next/headers";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("idp");
  return { title: t("title") };
}

export default async function Page(props: { searchParams: Promise<Record<string | number | symbol, string | undefined>> }) {
  const searchParams = await props.searchParams;

  const requestId = searchParams?.requestId;
  const organization = searchParams?.organization;

  const _headers = await headers();
  const { serviceConfig } = getServiceConfig(_headers);

  // LCMC: without ?organization= fall back to the default organization like /loginname does, so the
  // page shows its identity providers and branding instead of the instance's (upstream: organization only)
  let defaultOrganization;
  if (!organization) {
    const org: Organization | null = await getDefaultOrg({ serviceConfig });
    if (org) {
      defaultOrganization = org.id;
    }
  }

  const identityProviders = await getActiveIdentityProviders({
    serviceConfig,
    orgId: organization ?? defaultOrganization,
  }).then((resp) => {
    return resp.identityProviders;
  });

  const branding = await getBrandingSettings({ serviceConfig, organization: organization ?? defaultOrganization });

  return (
    <DynamicTheme branding={branding}>
      <div className="flex flex-col space-y-4">
        <h1>
          <Translated i18nKey="title" namespace="idp" />
        </h1>
        <p className="ztdl-p">
          <Translated i18nKey="description" namespace="idp" />
        </p>
      </div>

      <div className="w-full">
        {!!identityProviders?.length && (
          <SignInWithIdp
            identityProviders={identityProviders}
            requestId={requestId}
            organization={organization}
            postErrorRedirectUrl="/idp"
            showLabel={false}
          ></SignInWithIdp>
        )}
      </div>
    </DynamicTheme>
  );
}
